{- git-annex command
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Command.Add where

import Control.Monad.State (liftIO)
import System.Posix.Files
import System.Directory

import Command
import qualified Annex
import Utility
import Locations
import qualified Backend
import LocationLog
import Types
import Core

{- The add subcommand annexes a file, storing it in a backend, and then
 - moving it into the annex directory and setting up the symlink pointing
 - to its content. -}
start :: SubCmdStartBackendFile
start pair@(file, _) = notAnnexed file $ do
	s <- liftIO $ getSymbolicLinkStatus file
	if ((isSymbolicLink s) || (not $ isRegularFile s))
		then return Nothing
		else do
			showStart "add" file
			return $ Just $ perform pair

perform :: (FilePath, Maybe Backend) -> SubCmdPerform
perform (file, backend) = do
	stored <- Backend.storeFileKey file backend
	case (stored) of
		Nothing -> return Nothing
		Just (key, _) -> return $ Just $ cleanup file key

cleanup :: FilePath -> Key -> SubCmdCleanup
cleanup file key = do
	logStatus key ValuePresent
	g <- Annex.gitRepo
	let dest = annexLocation g key
	liftIO $ createDirectoryIfMissing True (parentDir dest)
	liftIO $ renameFile file dest
	link <- calcGitLink file key
	liftIO $ createSymbolicLink link file
	Annex.queue "add" [] file
	return True