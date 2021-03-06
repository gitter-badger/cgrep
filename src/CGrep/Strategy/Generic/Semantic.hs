--
-- Copyright (c) 2013 Bonelli Nicola <bonelli@antifork.org>
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
--

module CGrep.Strategy.Generic.Semantic (search) where

import qualified Data.ByteString.Char8 as C
import qualified CGrep.Parser.Generic.Token as Generic

import CGrep.Filter
import CGrep.Lang
import CGrep.Common
import CGrep.Output

import CGrep.Parser.Token
import CGrep.Parser.WildCard

import Control.Monad.Trans.Reader
import Control.Monad.IO.Class

import Data.List
import Data.Function
import Data.Maybe

import Options
import Debug
import Util


search :: FilePath -> [Text8] -> ReaderT Options IO [Output]
search f ps = do

    opt <- ask
    text <- liftIO $ getTargetContents f

    let filename = getTargetName f

    -- transform text

    let text' = ignoreCase opt text

        filt  = (mkContextFilter opt) { getFilterComment = False }

    -- pre-process patterns

        patterns   = map (Generic.tokenizer . contextFilter (getFileLang opt filename) filt) ps  -- [ [t1,t2,..], [t1,t2...] ]
        patterns'  = map (map mkWildCardFromToken) patterns                                      -- [ [w1,w2,..], [w1,w2,..] ]
        patterns'' = map (combineMultiCard . map (:[])) patterns'                                -- [ [m1,m2,..], [m1,m2,..] ] == [[[w1], [w2],..], [[w1],[w2],..]]

    -- quickSearch ...

        ps' = mapMaybe (\x -> case x of
                            TokenCard (Generic.TokenLiteral xs _) -> Just (rmQuote $ trim xs)
                            TokenCard (Generic.TokenAlpha "OR" _) -> Nothing
                            TokenCard t                           -> Just (tkToString t)
                            _                                     -> Nothing
                            ) . concat $ patterns'

    -- put banners...

    putStrLevel1 $ "strategy  : running generic semantic search on " ++ filename ++ "..."
    putStrLevel2 $ "wildcards : " ++ show patterns'
    putStrLevel2 $ "multicards: " ++ show patterns''
    putStrLevel2 $ "identif   : " ++ show ps'


    runQuickSearch filename (quickSearch opt (map C.pack ps') text') $ do

        -- context filter

        let text'' = contextFilter (getFileLang opt filename) filt text'

        -- expand multi-line

            text''' = expandMultiline opt text''

        -- parse source code, get the Generic.Token list...

            tokens = Generic.tokenizer text'''

        -- get matching tokens ...

            tokens' = sortBy (compare `on` Generic.toOffset) $ nub $ concatMap (\ms -> filterTokensWithMultiCards opt ms tokens) patterns''

            matches = map (\t -> let n = fromIntegral (Generic.toOffset t) in (n, Generic.toString t)) tokens' :: [(Int, String)]

        putStrLevel2 $ "tokens    : " ++ show tokens'
        putStrLevel2 $ "matches   : " ++ show matches
        putStrLevel3 $ "---\n" ++ C.unpack text''' ++ "\n---"

        mkOutput filename text text''' matches

