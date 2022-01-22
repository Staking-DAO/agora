module Agora.AuthorityToken (authorityTokenPolicy, AuthorityToken (..), serialisedScriptSize) where

--------------------------------------------------------------------------------

import Data.Proxy (Proxy (..))
import Prelude

--------------------------------------------------------------------------------

import Codec.Serialise (serialise)
import Data.ByteString qualified as BSS
import Data.ByteString.Lazy qualified as BS
import Data.ByteString.Short qualified as SBS

--------------------------------------------------------------------------------

import Cardano.Api.Shelley (
  PlutusScript (PlutusScriptSerialised),
  PlutusScriptV1,
  serialiseToCBOR,
 )
import Plutus.V1.Ledger.Scripts (Script)
import Plutus.V1.Ledger.Value (AssetClass (..))

--------------------------------------------------------------------------------

import Plutarch.Api.V1 hiding (PMaybe (..))
import Plutarch.Bool (PBool, PEq, pif, (#<), (#==))
import Plutarch.Builtin (PBuiltinPair, PData, pdata, pfromData, pfstBuiltin, psndBuiltin)
import Plutarch.DataRepr (pindexDataList)
import Plutarch.Integer (PInteger)
import Plutarch.Lift (pconstant)
import Plutarch.List (PIsListLike, pfoldr', precList)
import Plutarch.Maybe (PMaybe (PJust, PNothing))
import Plutarch.Prelude
import Plutarch.Trace (ptraceError)
import Plutarch.Unit (PUnit)

--------------------------------------------------------------------------------

{- | An AuthorityToken represents a proof that a particular token moved while this token was minted.
 In effect, this means that the validator that locked such a token must have approved said transaction.
 Said validator should be made aware of _this_ token's existence in order to prevent incorrect minting.
-}
data AuthorityToken = AuthorityToken
  { -- | Token that must move in order for minting this to be valid.
    authority :: AssetClass
  }

--------------------------------------------------------------------------------

-- TODO: upstream something like this
pfind' :: PIsListLike list a => (Term s a -> Term s PBool) -> Term s (list a :--> PMaybe a)
pfind' p =
  precList
    (\self x xs -> pif (p x) (pcon (PJust x)) (self # xs))
    (const $ pcon PNothing)

-- TODO: upstream something like this
plookup :: (PEq a, PIsListLike list (PBuiltinPair a b)) => Term s (a :--> list (PBuiltinPair a b) :--> PMaybe b)
plookup =
  phoistAcyclic $
    plam $ \k xs ->
      pmatch (pfind' (\p -> pfstBuiltin # p #== k) # xs) $ \case
        PNothing -> pcon PNothing
        PJust p -> pcon (PJust (psndBuiltin # p))

passetClassValueOf' :: AssetClass -> Term s (PValue :--> PInteger)
passetClassValueOf' (AssetClass (sym, token)) =
  passetClassValueOf # pconstant sym # pconstant token

passetClassValueOf :: Term s (PCurrencySymbol :--> PTokenName :--> PValue :--> PInteger)
passetClassValueOf =
  phoistAcyclic $
    plam $ \sym token value'' ->
      pmatch value'' $ \(PValue value') ->
        pmatch value' $ \(PMap value) ->
          pmatch (plookup # pdata sym # value) $ \case
            PNothing -> 0
            PJust m' ->
              pmatch (pfromData m') $ \(PMap m) ->
                pmatch (plookup # pdata token # m) $ \case
                  PNothing -> 0
                  PJust v -> pfromData v

-- TODO: We should rely on plutus-extra instead of rolling our own, this is just quick & hacky.
serialisedScriptSize :: Script -> Int
serialisedScriptSize =
  BSS.length
    . serialiseToCBOR
    . PlutusScriptSerialised @PlutusScriptV1
    . SBS.toShort
    . BS.toStrict
    . serialise

authorityTokenPolicy :: AuthorityToken -> Term s (PData :--> PData :--> PScriptContext :--> PUnit)
authorityTokenPolicy params =
  plam $ \_datum _redeemer ctx' ->
    pmatch ctx' $ \(PScriptContext ctx) ->
      let txInfo' =
            pfromData $ pindexDataList (Proxy @0) # ctx

          purpose' =
            pfromData $ pindexDataList (Proxy @1) # ctx

          inputs =
            pmatch txInfo' $ \(PTxInfo txInfo) ->
              pfromData $ pindexDataList (Proxy @0) # txInfo

          authorityTokenInputs =
            pfoldr'
              ( \txInInfo' acc ->
                  pmatch (pfromData txInInfo') $ \(PTxInInfo txInInfo) ->
                    let txOut' = pfromData $ pindexDataList (Proxy @1) # txInInfo
                        txOutValue = pmatch txOut' $ \(PTxOut txOut) -> pfromData $ pindexDataList (Proxy @1) # txOut
                     in passetClassValueOf' params.authority # txOutValue + acc
              )
              # (0 :: Term s PInteger)
              # inputs

          -- We incur the cost twice here. This will be fixed upstream in Plutarch.
          mintedValue =
            pmatch txInfo' $ \(PTxInfo txInfo) ->
              pfromData $ pindexDataList (Proxy @3) # txInfo

          tokenMoved = 0 #< authorityTokenInputs
       in pmatch purpose' $ \case
            PMinting sym' ->
              let sym = pfromData $ pindexDataList (Proxy @0) # sym'
                  mintedATs = passetClassValueOf # sym # pconstant "" # mintedValue
               in pif
                    (0 #< mintedATs)
                    ( pif
                        tokenMoved
                        -- The authority token moved, we are good to go for minting.
                        (pconstant ())
                        (ptraceError "Authority token did not move in minting GATs")
                    )
                    -- We minted 0 or less Authority Tokens, we are good to go.
                    -- Burning is always allowed.
                    (pconstant ())
            _ ->
              ptraceError "Wrong script type"
