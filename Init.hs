{- git-annex repository initialization
 -
 - Copyright 2011 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Init (
	ensureInitialized,
	initialize,
	uninitialize
) where

import Control.Monad.State (liftIO)
import Control.Monad (unless)
import System.Directory

import qualified Annex
import qualified Git
import qualified Branch
import Version
import Messages
import Types
import Utility
import Utility.Conditional
import UUID

initialize :: Annex ()
initialize = do
	prepUUID
	Branch.create
	setVersion
	gitPreCommitHookWrite

uninitialize :: Annex ()
uninitialize = do
	gitPreCommitHookUnWrite

{- Will automatically initialize if there is already a git-annex
   branch from somewhere. Otherwise, require a manual init
   to avoid git-annex accidentially being run in git
   repos that did not intend to use it. -}
ensureInitialized :: Annex ()
ensureInitialized = getVersion >>= maybe needsinit checkVersion
	where
		needsinit = do
			annexed <- Branch.hasSomeBranch
			if annexed
				then initialize
				else error "First run: git-annex init"

{- set up a git pre-commit hook, if one is not already present -}
gitPreCommitHookWrite :: Annex ()
gitPreCommitHookWrite = unlessBare $ do
	hook <- preCommitHook
	exists <- liftIO $ doesFileExist hook
	if exists
		then warning $ "pre-commit hook (" ++ hook ++ ") already exists, not configuring"
		else liftIO $ do
			viaTmp writeFile hook preCommitScript
			p <- getPermissions hook
			setPermissions hook $ p {executable = True}

gitPreCommitHookUnWrite :: Annex ()
gitPreCommitHookUnWrite = unlessBare $ do
	hook <- preCommitHook
	whenM (liftIO $ doesFileExist hook) $ do
		c <- liftIO $ readFile hook
		if c == preCommitScript
			then liftIO $ removeFile hook
			else warning $ "pre-commit hook (" ++ hook ++ 
				") contents modified; not deleting." ++
				" Edit it to remove call to git annex."

unlessBare :: Annex () -> Annex ()
unlessBare a = do
	g <- Annex.gitRepo
	unless (Git.repoIsLocalBare g) a

preCommitHook :: Annex FilePath
preCommitHook = do
	g <- Annex.gitRepo
	return $ Git.gitDir g ++ "/hooks/pre-commit"

preCommitScript :: String
preCommitScript = 
		"#!/bin/sh\n" ++
		"# automatically configured by git-annex\n" ++ 
		"git annex pre-commit .\n"
