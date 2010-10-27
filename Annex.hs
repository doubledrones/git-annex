{- git-annex monad
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Annex (
	new,
	run,
	gitRepo,
	gitRepoChange,
	backends,
	backendsChange,
	supportedBackends,
	flagIsSet,
	flagChange,
	flagGet,
	Flag(..),
	queue,
	queueGet
) where

import Control.Monad.State
import qualified Data.Map as M

import qualified GitRepo as Git
import qualified GitQueue
import Types
import qualified TypeInternals as Internals

{- Create and returns an Annex state object for the specified git repo. -}
new :: Git.Repo -> [Backend] -> IO AnnexState
new gitrepo allbackends = do
	let s = Internals.AnnexState {
		Internals.repo = gitrepo,
		Internals.backends = [],
		Internals.supportedBackends = allbackends,
		Internals.flags = M.empty,
		Internals.repoqueue = GitQueue.empty
	}
	(_,s') <- Annex.run s (prep gitrepo)
	return s'
	where
		prep gitrepo = do
			-- read git config and update state
			gitrepo' <- liftIO $ Git.configRead gitrepo
			Annex.gitRepoChange gitrepo'

{- performs an action in the Annex monad -}
run state action = runStateT (action) state

{- Returns the git repository being acted on -}
gitRepo :: Annex Git.Repo
gitRepo = do
	state <- get
	return (Internals.repo state)

{- Changes the git repository being acted on. -}
gitRepoChange :: Git.Repo -> Annex ()
gitRepoChange r = do
	state <- get
	put state { Internals.repo = r }
	return ()

{- Returns the backends being used. -}
backends :: Annex [Backend]
backends = do
	state <- get
	return (Internals.backends state)

{- Sets the backends to use. -}
backendsChange :: [Backend] -> Annex ()
backendsChange b = do
	state <- get
	put state { Internals.backends = b }
	return ()

{- Returns the full list of supported backends. -}
supportedBackends :: Annex [Backend]
supportedBackends = do
	state <- get
	return (Internals.supportedBackends state)

{- Return True if a Bool flag is set. -}
flagIsSet :: FlagName -> Annex Bool
flagIsSet name = do
	state <- get
	case (M.lookup name $ Internals.flags state) of
		Just (FlagBool True) -> return True
		_ -> return False 

{- Sets the value of a flag. -}
flagChange :: FlagName -> Flag -> Annex ()
flagChange name val = do
	state <- get
	put state { Internals.flags = M.insert name val $ Internals.flags state }
	return ()

{- Gets the value of a String flag (or "" if there is no such String flag) -}
flagGet :: FlagName -> Annex String
flagGet name = do
	state <- get
	case (M.lookup name $ Internals.flags state) of
		Just (FlagString s) -> return s
		_ -> return ""

{- Adds a git command to the queue. -}
queue :: String -> [String] -> FilePath -> Annex ()
queue subcommand params file = do
	state <- get
	let q = Internals.repoqueue state
	put state { Internals.repoqueue = GitQueue.add q subcommand params file }

{- Returns the queue. -}
queueGet :: Annex GitQueue.Queue
queueGet = do
	state <- get
	return (Internals.repoqueue state)
