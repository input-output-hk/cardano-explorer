{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Explorer.Node.Insert.Genesis
  ( insertGenesisDistribution
  , validateGenesisTxs
  ) where

import           Cardano.Prelude

import           Cardano.Binary (Raw)
import qualified Cardano.Crypto as Crypto

import           Cardano.BM.Trace (Trace, logInfo)
import qualified Cardano.Chain.Common as Ledger
import qualified Cardano.Chain.Genesis as Ledger
import qualified Cardano.Chain.UTxO as Ledger

import           Control.Monad (void)
import           Control.Monad.IO.Class (MonadIO)
import           Control.Monad.Trans.Reader (ReaderT)

import qualified Data.ByteArray
import           Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import           Data.Text (Text)

import           Database.Persist.Sql (SqlBackend)

import qualified Explorer.DB as DB


-- | Idempotent insert the initial Genesis distribution transactions into the DB.
-- If these transactions are already in the DB, they are validated.
insertGenesisDistribution :: Trace IO Text -> Ledger.Config -> IO ()
insertGenesisDistribution tracer cfg = do
    -- TODO: This is idempotent, but probably better to check if its already been done
    -- and validate if it has.
    -- This is how logging is turned on and off.
    -- The logging is incredibly verbose and probably only useful for debugging.
    if False
      then DB.runDbIohkLogging tracer insertAction
      else DB.runDbNoLogging insertAction
    logInfo tracer $ "Initial genesis distribution populated."
  where
    insertAction :: MonadIO m => ReaderT SqlBackend m ()
    insertAction = do
        -- Insert an 'artificial' Genesis block.
        bid <- fmap both . DB.insertBlock
                            $ DB.Block
                                { DB.blockHash = genesisHash
                                , DB.blockSlotNo = Nothing
                                , DB.blockBlockNo = 0
                                , DB.blockPrevious = Nothing
                                , DB.blockMerkelRoot = Nothing
                                , DB.blockSize = 0
                                }

        mapM_ (insertTxOuts bid) $ genesisTxos cfg

    genesisHash :: ByteString
    genesisHash = unAbstractHash (Ledger.unGenesisHash $ Ledger.configGenesisHash cfg)

-- | Validate that the initial Genesis distribution in the DB matches the Genesis data.
validateGenesisTxs :: MonadIO m => Crypto.Hash Raw -> m ()
validateGenesisTxs _gh =
  -- TODO: Need to write a query and then check the result of the query.
  pure ()

-- -----------------------------------------------------------------------------

insertTxOuts :: MonadIO m => DB.BlockId -> (Ledger.Address, Ledger.Lovelace) -> ReaderT SqlBackend m ()
insertTxOuts blkId (address, value) = do
  -- Each address/value pair of the initial coin distribution comes from an artifical transaction
  -- with a hash generated by hashing the address.
  txId <- fmap both . DB.insertTx $
                            DB.Tx
                              { DB.txHash = unTxHash $ txHashOfAddress address
                              , DB.txBlock = blkId
                              , DB.txFee = 0
                              }
  void . DB.insertTxOut $
            DB.TxOut
              { DB.txOutTxId = txId
              , DB.txOutIndex = 0
              , DB.txOutAddress = unAddressHash $ Ledger.addrRoot address
              , DB.txOutValue = Ledger.unsafeGetLovelace value
              }


txHashOfAddress :: Ledger.Address -> Crypto.Hash Ledger.Tx
txHashOfAddress = coerce . Crypto.hash

unTxHash :: Crypto.Hash Ledger.Tx -> ByteString
unTxHash = Data.ByteArray.convert

-- Put this here until this function goes in cardano-ledger.
unAddressHash :: Ledger.AddressHash Ledger.Address' -> ByteString
unAddressHash = Data.ByteArray.convert

unAbstractHash :: Crypto.Hash Raw -> ByteString
unAbstractHash = Data.ByteArray.convert

genesisTxos :: Ledger.Config -> [(Ledger.Address, Ledger.Lovelace)]
genesisTxos config =
    avvmBalances <> nonAvvmBalances
  where
    avvmBalances :: [(Ledger.Address, Ledger.Lovelace)]
    avvmBalances =
      first (Ledger.makeRedeemAddress networkMagic)
        <$> Map.toList (Ledger.unGenesisAvvmBalances $ Ledger.configAvvmDistr config)

    networkMagic :: Ledger.NetworkMagic
    networkMagic = Ledger.makeNetworkMagic (Ledger.configProtocolMagic config)

    nonAvvmBalances :: [(Ledger.Address, Ledger.Lovelace)]
    nonAvvmBalances =
      Map.toList $ Ledger.unGenesisNonAvvmBalances (Ledger.configNonAvvmBalances config)

both :: Either a a -> a
both (Left a) = a
both (Right a) = a
