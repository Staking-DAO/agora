{- |
Module     : Spec.Sample.Governor
Maintainer : connor@mlabs.city
Description: Sample based testing for Governor utxos

This module tests primarily the happy path for Governor interactions
-}
module Spec.Sample.Governor (
  proposalCreation,
  mutateState,
  mintGAT,
  mintGST,
) where

--------------------------------------------------------------------------------

import Plutarch.Api.V1 (mkValidator, validatorHash)
import Plutarch.SafeMoney.Tagged

--------------------------------------------------------------------------------

import Plutus.V1.Ledger.Address (scriptHashAddress)
import Plutus.V1.Ledger.Api (
  Address (..),
  Credential (PubKeyCredential),
  Datum (..),
  PubKeyHash,
  ScriptContext (..),
  ScriptPurpose (Minting, Spending),
  ToData (toBuiltinData),
  TokenName (..),
  TxInInfo (TxInInfo),
  TxInfo (..),
  TxOut (..),
  TxOutRef (..),
  Validator,
  ValidatorHash (..),
 )
import Plutus.V1.Ledger.Interval qualified as Interval
import Plutus.V1.Ledger.Scripts (unitDatum)
import Plutus.V1.Ledger.Value (
  AssetClass (..),
 )
import Plutus.V1.Ledger.Value qualified as Value
import PlutusTx.AssocMap qualified as AssocMap

--------------------------------------------------------------------------------

import Agora.Effect.NoOp
import Agora.Governor
import Agora.Proposal
import Agora.Proposal qualified as P
import Agora.Stake

--------------------------------------------------------------------------------

import Spec.Sample.Shared
import Spec.Util (datumPair, toDatumHash)

--------------------------------------------------------------------------------

-- | This script context should be a valid transaction.
mintGST :: ScriptContext
mintGST =
  let gst = Value.assetClassValue govAssetClass 1

      ---

      governorOutputDatum' :: GovernorDatum
      governorOutputDatum' =
        GovernorDatum
          { proposalThresholds = defaultProposalThresholds
          , nextProposalId = ProposalId 0
          }
      governorOutputDatum :: Datum
      governorOutputDatum = Datum $ toBuiltinData governorOutputDatum'
      governorOutput :: TxOut
      governorOutput =
        TxOut
          { txOutAddress = govValidatorAddress
          , txOutValue = withMinAda gst
          , txOutDatumHash = Just $ toDatumHash governorOutputDatum
          }

      ---

      witness :: PubKeyHash
      witness = "a926a9a72a0963f428e3252caa8354e655603996fb8892d6b8323fd072345924"
      witnessAddress :: Address
      witnessAddress = Address (PubKeyCredential witness) Nothing

      ---

      witnessInput :: TxOut
      witnessInput =
        TxOut
          { txOutAddress = witnessAddress
          , txOutValue = mempty
          , txOutDatumHash = Nothing
          }
      witnessUTXO :: TxInInfo
      witnessUTXO = TxInInfo gstUTXORef witnessInput

      ---

      witnessOutput :: TxOut
      witnessOutput =
        TxOut
          { txOutAddress = witnessAddress
          , txOutValue = minAda
          , txOutDatumHash = Nothing
          }
   in ScriptContext
        { scriptContextTxInfo =
            TxInfo
              { txInfoInputs =
                  [ witnessUTXO
                  ]
              , txInfoOutputs = [governorOutput, witnessOutput]
              , txInfoFee = Value.singleton "" "" 2
              , txInfoMint = gst
              , txInfoDCert = []
              , txInfoWdrl = []
              , txInfoValidRange = Interval.always
              , txInfoSignatories = [witness]
              , txInfoData = [datumPair governorOutputDatum]
              , txInfoId = "90906d3e6b4d6dec2e747dcdd9617940ea8358164c7244694cfa39dec18bd9d4"
              }
        , scriptContextPurpose = Minting govSymbol
        }

-- | This script context should be a valid transaction.
proposalCreation :: ScriptContext
proposalCreation =
  let pst = Value.singleton proposalPolicySymbol "" 1
      gst = Value.assetClassValue govAssetClass 1
      sst = Value.assetClassValue stakeAssetClass 1
      stackedGTs = 424242424242
      thisProposalId = ProposalId 0

      ---

      governorInputDatum' :: GovernorDatum
      governorInputDatum' =
        GovernorDatum
          { proposalThresholds = defaultProposalThresholds
          , nextProposalId = thisProposalId
          }
      governorInputDatum :: Datum
      governorInputDatum = Datum $ toBuiltinData governorInputDatum'
      governorInput :: TxOut
      governorInput =
        TxOut
          { txOutAddress = govValidatorAddress
          , txOutValue = gst
          , txOutDatumHash = Just $ toDatumHash governorInputDatum
          }

      ---

      effects =
        AssocMap.fromList
          [ (ResultTag 0, [])
          , (ResultTag 1, [])
          ]
      proposalDatum :: Datum
      proposalDatum =
        Datum
          ( toBuiltinData $
              ProposalDatum
                { P.proposalId = ProposalId 0
                , effects = effects
                , status = Draft
                , cosigners = [signer]
                , thresholds = defaultProposalThresholds
                , votes = emptyVotesFor effects
                }
          )
      proposalOutput :: TxOut
      proposalOutput =
        TxOut
          { txOutAddress = proposalValidatorAddress
          , txOutValue = withMinAda pst
          , txOutDatumHash = Just (toDatumHash proposalDatum)
          }

      ---

      stakeInputDatum' :: StakeDatum
      stakeInputDatum' =
        StakeDatum
          { stakedAmount = Tagged stackedGTs
          , owner = signer
          , lockedBy = []
          }
      stakeInputDatum :: Datum
      stakeInputDatum = Datum $ toBuiltinData stakeInputDatum'
      stakeInput :: TxOut
      stakeInput =
        TxOut
          { txOutAddress = stakeAddress
          , txOutValue = sst <> Value.assetClassValue (untag stake.gtClassRef) stackedGTs
          , txOutDatumHash = Just (toDatumHash stakeInputDatum)
          }

      ---
      governorOutputDatum' :: GovernorDatum
      governorOutputDatum' = governorInputDatum' {nextProposalId = getNextProposalId thisProposalId}
      governorOutputDatum :: Datum
      governorOutputDatum = Datum $ toBuiltinData governorOutputDatum'
      governorOutput :: TxOut
      governorOutput =
        governorInput
          { txOutDatumHash = Just $ toDatumHash governorOutputDatum
          , txOutValue = withMinAda gst
          }

      ---

      proposalLocks :: [ProposalLock]
      proposalLocks =
        [ ProposalLock (ResultTag 0) thisProposalId
        , ProposalLock (ResultTag 1) thisProposalId
        ]
      stakeOutputDatum' :: StakeDatum
      stakeOutputDatum' = stakeInputDatum' {lockedBy = proposalLocks}
      stakeOutputDatum :: Datum
      stakeOutputDatum = Datum $ toBuiltinData stakeOutputDatum'
      stakeOutput :: TxOut
      stakeOutput =
        stakeInput
          { txOutDatumHash = Just $ toDatumHash stakeOutputDatum
          , txOutValue = withMinAda sst <> Value.assetClassValue (untag stake.gtClassRef) stackedGTs
          }

      ---
      ownInputRef :: TxOutRef
      ownInputRef = TxOutRef "4355a46b19d348dc2f57c046f8ef63d4538ebb936000f3c9ee954a27460dd865" 1
   in ScriptContext
        { scriptContextTxInfo =
            TxInfo
              { txInfoInputs =
                  [ TxInInfo
                      ownInputRef
                      governorInput
                  , TxInInfo
                      (TxOutRef "4262bbd0b3fc926b74eaa8abab5def6ce5e6b94f19cf221c02a16e7da8cd470f" 1)
                      stakeInput
                  ]
              , txInfoOutputs = [proposalOutput, governorOutput, stakeOutput]
              , txInfoFee = Value.singleton "" "" 2
              , txInfoMint = pst
              , txInfoDCert = []
              , txInfoWdrl = []
              , txInfoValidRange = Interval.always
              , txInfoSignatories = [signer]
              , txInfoData =
                  datumPair
                    <$> [ governorInputDatum
                        , governorOutputDatum
                        , proposalDatum
                        , stakeInputDatum
                        , stakeOutputDatum
                        ]
              , txInfoId = "1ffb9669335c908d9a4774a4bf7aa7bfafec91d015249b4138bc83fde4a3330a"
              }
        , scriptContextPurpose = Spending ownInputRef
        }

-- | This script context should be a valid transaction.
mintGAT :: ScriptContext
mintGAT =
  let pst = Value.singleton proposalPolicySymbol "" 1
      gst = Value.assetClassValue govAssetClass 1
      gat = Value.assetClassValue atAssetClass 1

      ---

      mockEffect :: Validator
      mockEffect = mkValidator $ noOpValidator ""
      mockEffectHash :: ValidatorHash
      mockEffectHash = validatorHash mockEffect
      mockEffectAddress :: Address
      mockEffectAddress = scriptHashAddress mockEffectHash
      mockEffectOutputDatum :: Datum
      mockEffectOutputDatum = unitDatum
      atTokenName :: TokenName
      atTokenName = TokenName hash
        where
          ValidatorHash hash = mockEffectHash
      atAssetClass :: AssetClass
      atAssetClass = AssetClass (authorityTokenSymbol, atTokenName)

      ---

      governorInputDatum' :: GovernorDatum
      governorInputDatum' =
        GovernorDatum
          { proposalThresholds = defaultProposalThresholds
          , nextProposalId = ProposalId 5
          }
      governorInputDatum :: Datum
      governorInputDatum = Datum $ toBuiltinData governorInputDatum'
      governorInput :: TxOut
      governorInput =
        TxOut
          { txOutAddress = govValidatorAddress
          , txOutValue = gst
          , txOutDatumHash = Just $ toDatumHash governorInputDatum
          }

      ---

      effects =
        AssocMap.fromList
          [ (ResultTag 0, [])
          , (ResultTag 1, [(mockEffectHash, toDatumHash mockEffectOutputDatum)])
          ]
      proposalVotes :: ProposalVotes
      proposalVotes =
        ProposalVotes $
          AssocMap.fromList
            [ (ResultTag 0, 100)
            , (ResultTag 1, 2000) -- The winner
            ]
      proposalInputDatum' :: ProposalDatum
      proposalInputDatum' =
        ProposalDatum
          { P.proposalId = ProposalId 0
          , effects = effects
          , status = Locked
          , -- TODO: Any need to check minimun amount of cosigners here?
            cosigners = [signer, signer2]
          , thresholds = defaultProposalThresholds
          , votes = proposalVotes
          }
      proposalInputDatum :: Datum
      proposalInputDatum = Datum $ toBuiltinData proposalInputDatum'
      proposalInput :: TxOut
      proposalInput =
        TxOut
          { txOutAddress = proposalValidatorAddress
          , txOutValue = pst
          , txOutDatumHash = Just (toDatumHash proposalInputDatum)
          }

      ---

      governorOutputDatum' :: GovernorDatum
      governorOutputDatum' = governorInputDatum'
      governorOutputDatum :: Datum
      governorOutputDatum = Datum $ toBuiltinData governorOutputDatum'
      governorOutput :: TxOut
      governorOutput =
        governorInput
          { txOutDatumHash = Just $ toDatumHash governorOutputDatum
          , txOutValue = withMinAda gst
          }

      ---

      proposalOutputDatum' :: ProposalDatum
      proposalOutputDatum' = proposalInputDatum' {status = Finished}
      proposalOutputDatum :: Datum
      proposalOutputDatum = Datum $ toBuiltinData proposalOutputDatum'
      proposalOutput :: TxOut
      proposalOutput =
        proposalInput
          { txOutDatumHash = Just $ toDatumHash proposalOutputDatum
          , txOutValue = withMinAda pst
          }

      --

      mockEffectOutput :: TxOut
      mockEffectOutput =
        TxOut
          { txOutAddress = mockEffectAddress
          , txOutDatumHash = Just $ toDatumHash mockEffectOutputDatum
          , txOutValue = withMinAda gat
          }

      --

      ownInputRef :: TxOutRef
      ownInputRef = TxOutRef "4355a46b19d348dc2f57c046f8ef63d4538ebb936000f3c9ee954a27460dd865" 1
   in ScriptContext
        { scriptContextTxInfo =
            TxInfo
              { txInfoInputs =
                  [ TxInInfo ownInputRef governorInput
                  , TxInInfo
                      (TxOutRef "11b2162f267614b803761032b6333040fc61478ae788c088614ee9487ab0c1b7" 1)
                      proposalInput
                  ]
              , txInfoOutputs =
                  [ governorOutput
                  , proposalOutput
                  , mockEffectOutput
                  ]
              , txInfoFee = Value.singleton "" "" 2
              , txInfoMint = gat
              , txInfoDCert = []
              , txInfoWdrl = []
              , txInfoValidRange = Interval.always
              , txInfoSignatories = [signer, signer2]
              , txInfoData =
                  datumPair
                    <$> [ governorInputDatum
                        , governorOutputDatum
                        , proposalInputDatum
                        , proposalOutputDatum
                        , mockEffectOutputDatum
                        ]
              , txInfoId = "ff755f613c1f7487dfbf231325c67f481f7a97e9faf4d8b09ad41176fd65cbe7"
              }
        , scriptContextPurpose = Spending ownInputRef
        }

-- | This script context should be a valid transaction.
mutateState :: ScriptContext
mutateState =
  let gst = Value.assetClassValue govAssetClass 1
      gat = Value.assetClassValue atAssetClass 1
      burntGAT = Value.assetClassValue atAssetClass (-1)

      ---

      -- TODO: Use the *real* effect, see https://github.com/Liqwid-Labs/agora/pull/62

      mockEffect :: Validator
      mockEffect = mkValidator $ noOpValidator ""
      mockEffectHash :: ValidatorHash
      mockEffectHash = validatorHash mockEffect
      mockEffectAddress :: Address
      mockEffectAddress = scriptHashAddress mockEffectHash
      atTokenName :: TokenName
      atTokenName = TokenName hash
        where
          ValidatorHash hash = mockEffectHash
      atAssetClass :: AssetClass
      atAssetClass = AssetClass (authorityTokenSymbol, atTokenName)

      --

      mockEffectInputDatum :: Datum
      mockEffectInputDatum = unitDatum
      mockEffectInput :: TxOut
      mockEffectInput =
        TxOut
          { txOutAddress = mockEffectAddress
          , txOutValue = gat -- Will be burnt
          , txOutDatumHash = Just $ toDatumHash mockEffectInputDatum
          }

      --

      mockEffectOutputDatum :: Datum
      mockEffectOutputDatum = mockEffectInputDatum
      mockEffectOutput :: TxOut
      mockEffectOutput =
        mockEffectInput
          { txOutValue = minAda
          , txOutDatumHash = Just $ toDatumHash mockEffectOutputDatum
          }

      --

      governorInputDatum' :: GovernorDatum
      governorInputDatum' =
        GovernorDatum
          { proposalThresholds = defaultProposalThresholds
          , nextProposalId = ProposalId 5
          }
      governorInputDatum :: Datum
      governorInputDatum = Datum $ toBuiltinData governorInputDatum'
      governorInput :: TxOut
      governorInput =
        TxOut
          { txOutAddress = govValidatorAddress
          , txOutValue = gst
          , txOutDatumHash = Just $ toDatumHash governorInputDatum
          }

      --

      governorOutputDatum' :: GovernorDatum
      governorOutputDatum' = governorInputDatum'
      governorOutputDatum :: Datum
      governorOutputDatum = Datum $ toBuiltinData governorOutputDatum'
      governorOutput :: TxOut
      governorOutput =
        governorInput
          { txOutDatumHash = Just $ toDatumHash governorOutputDatum
          , txOutValue = withMinAda gst
          }

      --

      ownInputRef :: TxOutRef
      ownInputRef = TxOutRef "f867238a04597c99a0b9858746557d305025cca3b9f78ea14d5c88c4cfcf58ff" 1
   in ScriptContext
        { scriptContextTxInfo =
            TxInfo
              { txInfoInputs =
                  [ TxInInfo ownInputRef governorInput
                  , TxInInfo
                      (TxOutRef "ecff06d7cf99089294569cc8b92609e44927278f9901730715d14634fbc10089" 1)
                      mockEffectInput
                  ]
              , txInfoOutputs =
                  [ governorOutput
                  , mockEffectOutput
                  ]
              , txInfoFee = Value.singleton "" "" 2
              , txInfoMint = burntGAT
              , txInfoDCert = []
              , txInfoWdrl = []
              , txInfoValidRange = Interval.always
              , txInfoSignatories = [signer, signer2]
              , txInfoData =
                  datumPair
                    <$> [ governorInputDatum
                        , governorOutputDatum
                        , mockEffectInputDatum
                        , mockEffectOutputDatum
                        ]
              , txInfoId = "9a12a605086a9f866731869a42d0558036fc739c74fea3849aa41562c015aaf9"
              }
        , scriptContextPurpose = Spending ownInputRef
        }
