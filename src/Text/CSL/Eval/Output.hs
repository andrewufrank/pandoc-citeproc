{-# LANGUAGE PatternGuards #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Text.CSL.Eval.Output
-- Copyright   :  (c) Andrea Rossato
-- License     :  BSD-style (see LICENSE)
--
-- Maintainer  :  Andrea Rossato <andrea.rossato@unitn.it>
-- Stability   :  unstable
-- Portability :  unportable
--
-- The CSL implementation
--
-----------------------------------------------------------------------------

module Text.CSL.Eval.Output where

import Text.CSL.Output.Plain
import Text.CSL.Style
import Text.ParserCombinators.Parsec hiding ( State (..) )

output :: Formatting -> String -> [Output]
output fm s
    | ' ':xs <- s = OSpace : output fm xs
    | []     <- s = []
    | otherwise   = [OStr s fm]

appendOutput :: Formatting -> [Output] -> [Output]
appendOutput fm xs = if xs /= [] then [Output xs fm] else []

outputList :: Formatting -> Delimiter -> [Output] -> [Output]
outputList fm d = appendOutput fm . addDelim d . map cleanOutput'
    where
      cleanOutput' o
          | Output xs f <- o = Output (cleanOutput xs) f
          | otherwise        = rmEmptyOutput o

cleanOutput :: [Output] -> [Output]
cleanOutput = flatten
    where
      flatten [] = []
      flatten (o:os)
          | ONull       <- o     = flatten os
          | Output xs f <- o
          , f == emptyFormatting = flatten xs ++ flatten os
          | otherwise            = rmEmptyOutput o : flatten os

rmEmptyOutput :: Output -> Output
rmEmptyOutput o
    | Output [] _ <- o = ONull
    | OStr []   _ <- o = ONull
    | OUrl t    _ <- o = if null (fst t) then ONull else o
    | otherwise        = o

addDelim :: String -> [Output] -> [Output]
addDelim d = foldr (\x xs -> if length xs < 1 then x : xs else check x xs) []
    where
      check x xs
          | ONull <- x = xs
          | otherwise  = let text = renderPlainStrict . formatOutputList
                         in  if d /= [] && text [x] /= [] && text xs /= []
                             then if head d == last (text [x]) && head d `elem` ".,;:!?"
                                  then x : ODel (tail d) : xs
                                  else x : ODel       d  : xs
                             else      x                 : xs

noOutputError :: Output
noOutputError = OStr "[CSL STYLE ERROR: reference with no printed form.]" emptyFormatting

noBibDataError :: Cite -> Output
noBibDataError c = OStr ("[CSL BIBLIOGRAPHIC DATA ERROR: reference " ++ show (citeId c) ++ " not found.]")
                   emptyFormatting

oStr :: String -> [Output]
oStr s = oStr' s emptyFormatting

oStr' :: String -> Formatting -> [Output]
oStr' [] _ = []
oStr' s  f = rtfParser f s

(<++>) :: [Output] -> [Output] -> [Output]
[] <++> o  = o
o  <++> [] = o
o1 <++> o2 = o1 ++ [OSpace] ++ o2

rtfTags :: [(String, (String,Formatting))]
rtfTags =
    [("b"                      , ("b"   , ef {fontWeight    = "bold"      }))
    ,("i"                      , ("i"   , ef {fontStyle     = "italic"    }))
    ,("sc"                     , ("sc"  , ef {fontVariant   = "small-caps"}))
    ,("sup"                    , ("sup" , ef {verticalAlign = "sup"       }))
    ,("sub"                    , ("sub" , ef {verticalAlign = "sub"       }))
    ,("span class=\"nocase\""  , ("span", ef {noCase        = True        }))
    ,("span class=\"nodecor\"" , ("span", ef {noDecor       = True        }))
    ]
    where
      ef = emptyFormatting

rtfParser :: Formatting -> String -> [Output]
rtfParser _ [] = []
rtfParser fm s
    = either (const [OStr s fm]) (return . flip Output fm . concat) $
      parse (manyTill parser eof) "" s
    where
      parser = parseText <|> parseMarkup

      parseText = do
        let amper = string "&" >> notFollowedBy (char '#') >>
                    return [OStr "&" emptyFormatting]
            apos  = string "'" >> return [OStr "’" emptyFormatting]
        x  <- many $ noneOf "<'\"`“‘&"
        xs <- parseQuotes <|> parseMarkup <|> amper <|> apos
        r  <- manyTill anyChar eof
        return (OStr x emptyFormatting : xs ++
                [Output (rtfParser emptyFormatting r) emptyFormatting])

      parseMarkup = do
        let tillTag = many $ noneOf "<"
        m   <- string "<" >> manyTill anyChar (try $ string ">")
        res <- case lookup m rtfTags of
                 Just tf -> do let ot = "<"  ++ fst tf ++ ">"
                                   ct = "</" ++ fst tf ++ ">"
                                   parseGreedy = do a <- tillTag
                                                    _ <- string ct
                                                    return a
                               x <- manyTill anyChar $ try $ string ct
                               y <- try parseGreedy <|> (string ot >> pzero) <|> return []
                               let r = if null y then x else x ++ ct ++ y
                               return [Output (rtfParser emptyFormatting r) (snd tf)]
                 Nothing -> do r <- tillTag
                               return [OStr ("<" ++ m ++ ">" ++ r) emptyFormatting]
        return [Output res emptyFormatting]

      parseQuotes = choice [parseQ "'" "'"
                           ,parseQ "\"" "\""
                           ,parseQ "``" "''"
                           ,parseQ "`" "'"
                           ,parseQ "“" "”"
                           ,parseQ "‘" "’"
                           ,parseQ "&#39;" "&#39;"
                           ,parseQ "&#34;" "&#34;"
                           ,parseQ "&quot;" "&quot;"
                           ,parseQ "&apos;" "&apos;"
                           ]
      parseQ a b = try $ do
        q <- string a >> manyTill anyChar (try $ string b >> notFollowedBy letter)
        return [Output (rtfParser emptyFormatting q) (emptyFormatting {quotes = ParsedQuote})]