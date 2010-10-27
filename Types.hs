{- git-annex abstract data types
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Types (
	Annex,
	AnnexState,
	Backend,
	Key,
	genKey,
	backendName,
	keyName,
	FlagName,
	Flag(..)
) where

import TypeInternals
