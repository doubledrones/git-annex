{- git-annex command line
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module CmdLine (parseCmd) where

import System.Console.GetOpt
import Control.Monad.State (liftIO)
import System.Directory
import Data.String.Utils
import Control.Monad (filterM)
import Monad (when)

import qualified GitRepo as Git
import qualified Annex
import Locations
import qualified Backend
import Types
import Core

import Command
import qualified Command.Add
import qualified Command.Unannex
import qualified Command.Drop
import qualified Command.Move
import qualified Command.Get
import qualified Command.FromKey
import qualified Command.DropKey
import qualified Command.SetKey
import qualified Command.Fix
import qualified Command.Init

data SubCommand = SubCommand {
	subcmdname :: String,
	subcmdparams :: String,
	subcmdseek :: SubCmdSeek,
	subcmddesc :: String
}
subCmds :: [SubCommand]
subCmds =  [
	  (SubCommand "add" path	(withFilesNotInGit Command.Add.start)
		"add files to annex")
	, (SubCommand "get" path	(withFilesInGit Command.Get.start)
		"make content of annexed files available")
	, (SubCommand "drop" path	(withFilesInGit Command.Drop.start)
		"indicate content of files not currently wanted")
	, (SubCommand "move" path	(withFilesInGit Command.Move.start)
		"transfer content of files to/from another repository")
	, (SubCommand "init" desc	(withDescription Command.Init.start)
		"initialize git-annex with repository description")
	, (SubCommand "unannex" path	(withFilesInGit Command.Unannex.start)
		"undo accidential add command")
	, (SubCommand "fix" path	(withFilesInGit Command.Fix.start)
		"fix up symlinks to point to annexed content")
	, (SubCommand "pre-commit" path (withFilesToBeCommitted Command.Fix.start)
		"fix up symlinks before they are committed")
	, (SubCommand "fromkey" key	(withFilesMissing Command.FromKey.start)
		"adds a file using a specific key")
	, (SubCommand "dropkey"	key	(withKeys Command.DropKey.start)
		"drops annexed content for specified keys")
	, (SubCommand "setkey" key	(withTempFile Command.SetKey.start)
		"sets annexed content for a key using a temp file")
	]
	where
		path = "PATH ..."
		key = "KEY ..."
		desc = "DESCRIPTION"

-- Each dashed command-line option results in generation of an action
-- in the Annex monad that performs the necessary setting.
options :: [OptDescr (Annex ())]
options = [
	    Option ['f'] ["force"] (NoArg (storebool "force" True))
		"allow actions that may lose annexed data"
	  , Option ['q'] ["quiet"] (NoArg (storebool "quiet" True))
		"avoid verbose output"
	  , Option ['v'] ["verbose"] (NoArg (storebool "quiet" False))
		"allow verbose output"
	  , Option ['b'] ["backend"] (ReqArg (storestring "backend") "NAME")
		"specify default key-value backend to use"
	  , Option ['k'] ["key"] (ReqArg (storestring "key") "KEY")
		"specify a key to use"
	  , Option ['t'] ["to"] (ReqArg (storestring "torepository") "REPOSITORY")
		"specify to where to transfer content"
	  , Option ['f'] ["from"] (ReqArg (storestring "fromrepository") "REPOSITORY")
		"specify from where to transfer content"
	  ]
	where
		storebool n b = Annex.flagChange n $ FlagBool b
		storestring n s = Annex.flagChange n $ FlagString s

header :: String
header = "Usage: git-annex " ++ (join "|" $ map subcmdname subCmds)

{- Usage message with lists of options and subcommands. -}
usage :: String
usage = usageInfo header options ++ "\nSubcommands:\n" ++ cmddescs
	where
		cmddescs = unlines $ map (\c -> indent $ showcmd c) subCmds
		showcmd c =
			(subcmdname c) ++
			(pad 11 (subcmdname c)) ++
			(subcmdparams c) ++
			(pad 13 (subcmdparams c)) ++
			(subcmddesc c)
		indent l = "  " ++ l
		pad n s = take (n - (length s)) $ repeat ' '

{- Prepares a list of actions to run to perform a subcommand, based on
 - the parameters passed to it. -}
prepSubCmd :: SubCommand -> AnnexState -> [String] -> IO [Annex Bool]
prepSubCmd SubCommand { subcmdseek = seek } state params = do
	list <- Annex.eval state $ seek params
	return $ map (\a -> doSubCmd a) list

{- Runs a subcommand through the start, perform and cleanup stages -}
doSubCmd :: SubCmdStart -> SubCmdCleanup
doSubCmd start = do
	s <- start
	case (s) of
		Nothing -> return True
		Just perform -> do
			p <- perform
			case (p) of
				Nothing -> do
					showEndFail
					return False
				Just cleanup -> do
					c <- cleanup
					if (c)
						then do
							showEndOk
							return True
						else do
							showEndFail
							return False

{- These functions find appropriate files or other things based on a
   user's parameters. -}
withFilesNotInGit :: SubCmdSeekBackendFiles
withFilesNotInGit a params = do
	repo <- Annex.gitRepo
	files <- liftIO $ mapM (Git.notInRepo repo) params
	let files' = foldl (++) [] files
	pairs <- Backend.chooseBackends files'
	return $ map a $ filter (\(f,_) -> notState f) pairs
withFilesInGit :: SubCmdSeekStrings
withFilesInGit a params = do
	repo <- Annex.gitRepo
	files <- liftIO $ mapM (Git.inRepo repo) params
	return $ map a $ filter notState $ foldl (++) [] files
withFilesMissing :: SubCmdSeekStrings
withFilesMissing a params = do
	files <- liftIO $ filterM missing params
	return $ map a $ filter notState files
	where
		missing f = do
			e <- doesFileExist f
			return $ not e
withDescription :: SubCmdSeekStrings
withDescription a params = do
	return $ [a $ unwords params]
withFilesToBeCommitted :: SubCmdSeekStrings
withFilesToBeCommitted a params = do
	repo <- Annex.gitRepo
	files <- liftIO $ mapM (Git.stagedFiles repo) params
	return $ map a $ filter notState $ foldl (++) [] files
withKeys :: SubCmdSeekStrings
withKeys a params = return $ map a params
withTempFile :: SubCmdSeekStrings
withTempFile a params = return $ map a params

{- filter out files from the state directory -}
notState :: FilePath -> Bool
notState f = stateLoc /= take (length stateLoc) f

{- Parses command line and returns two lists of actions to be 
 - run in the Annex monad. The first actions configure it
 - according to command line options, while the second actions
 - handle subcommands. -}
parseCmd :: [String] -> AnnexState -> IO ([Annex Bool], [Annex Bool])
parseCmd argv state = do
	(flags, params) <- getopt
	when (null params) $ error usage
	case lookupCmd (params !! 0) of
		[] -> error usage
		[subcommand] -> do
			actions <- prepSubCmd subcommand state (drop 1 params)
			let configactions = map (\flag -> do
				flag
				return True) flags
			return (configactions, actions)
		_ -> error "internal error: multiple matching subcommands"
	where
		getopt = case getOpt Permute options argv of
			(flags, params, []) -> return (flags, params)
			(_, _, errs) -> ioError (userError (concat errs ++ usage))
		lookupCmd cmd = filter (\c -> cmd  == subcmdname c) subCmds