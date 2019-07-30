{-# LANGUAGE OverloadedStrings #-}

module Explorer.DB.PGConfig
  ( PGConfig (..)
  , PGPassFile (..)
  , readPGConfigEnv
  , readPGPassFile
  , readPGPassFileExit
  , toConnectionString
  ) where

import           Control.Exception (IOException)
import qualified Control.Exception as Exception

import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as BS

import           Database.Persist.Postgresql (ConnectionString)

import           System.Environment (lookupEnv, setEnv)

-- | PGConfig as specified by https://www.postgresql.org/docs/11/libpq-pgpass.html
-- However, this module expects the config data to be on the first line.
data PGConfig = PGConfig
  { pgcHost :: ByteString
  , pgcPort :: ByteString
  , pgcDbname :: ByteString
  , pgcUser :: ByteString
  , pgcPassword :: ByteString
  } deriving Show

newtype PGPassFile
  = PGPassFile FilePath

toConnectionString :: PGConfig -> ConnectionString
toConnectionString pgc =
  BS.concat
    [ "host=", pgcHost pgc, " "
    , "port=", pgcPort pgc, " "
    , "user=", pgcUser pgc, " "
    , "dbname=", pgcDbname pgc, " "
    , "password=", pgcPassword pgc
    ]

-- | Read the PostgreSQL configuration from the file at the location specified by the
-- '$PGPASSFILE' environment variable.
readPGConfigEnv :: IO (Maybe PGConfig)
readPGConfigEnv = do
  mpath <- lookupEnv "PGPASSFILE"
  case mpath of
    Just fp -> readPGPassFile (PGPassFile fp)
    Nothing -> pure Nothing

-- | Read the PostgreSQL configuration from the specified file.
readPGPassFile :: PGPassFile -> IO (Maybe PGConfig)
readPGPassFile (PGPassFile fpath) = do
    either handler extract <$> Exception.try (BS.readFile fpath)
  where
    handler :: IOException -> Maybe a
    handler = const Nothing

    extract :: ByteString -> Maybe PGConfig
    extract bs =
      case BS.lines bs of
        (b:_) -> parseConfig b
        _ -> Nothing

    parseConfig :: ByteString -> Maybe PGConfig
    parseConfig bs =
      case BS.split ':' bs of
        [h, pt, d, u, pwd] -> Just $ PGConfig h pt d u pwd
        _ -> Nothing

-- | Read 'PGPassFile' into 'PGConfig'.
-- If it fails it will raise an error.
-- If it succeeds, it will set the 'PGPASSFILE' environment variable.
readPGPassFileExit :: PGPassFile -> IO PGConfig
readPGPassFileExit pgpassfile@(PGPassFile fpath) = do
  mc <- readPGPassFile pgpassfile
  case mc of
    Nothing -> error $ "Not able to read PGPassFile at " ++ show fpath ++ "."
    Just pgc -> do
      setEnv "PGPASSFILE" fpath
      pure pgc
