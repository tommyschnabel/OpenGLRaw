module Main where

import Control.Monad
import Data.Char
import Data.List
import qualified Data.Map as Map
import System.Console.GetOpt
import System.Environment
import qualified Registry as R
import MangledRegistry

data Option
  = PrintXML
  | PrintRaw
  | PrintProcessed
  | PrintEnums
  | PrintCommands
  | PrintCommandTypes
  deriving Eq

options :: [OptDescr Option]
options =
  [ Option ['x'] ["print-xml"] (NoArg PrintXML) "print XML"
  , Option ['r'] ["print-raw"] (NoArg PrintRaw) "print raw registry"
  , Option ['p'] ["print-processed"] (NoArg PrintProcessed) "print processed registry"
  , Option ['e'] ["print-enums"] (NoArg PrintEnums) "print enums"
  , Option ['c'] ["print-commands"] (NoArg PrintCommands) "print commands"
  , Option ['t'] ["print-command-types"] (NoArg PrintCommandTypes) "print command types" ]

getPaths :: IO ([Option], FilePath)
getPaths = do
  args <- getArgs
  case getOpt Permute options args of
    (opts, [path], []) -> return (opts, path)
    (_, _, errs) -> do
       n <- getProgName
       let header = "Usage: " ++ n ++ " [OPTION]... file"
       ioError (userError (concat errs ++ usageInfo header options))

main :: IO ()
main = do
  (opts, path) <- getPaths
  str <- readFile path
  when (PrintXML `elem` opts) $ do
    putStrLn "---------------------------------------- XML registry"
    either putStrLn (putStrLn . R.unparseRegistry) $ R.parseRegistry str
  when (PrintRaw `elem` opts) $ do
    putStrLn "---------------------------------------- raw registry"
    either putStrLn print $ R.parseRegistry str
  when (PrintProcessed `elem` opts) $ do
    putStrLn "---------------------------------------- processed registry"
    either putStrLn print $ parseRegistry str
  when (PrintEnums `elem` opts) $ do
    putStrLn "---------------------------------------- enums"
    either putStrLn (mapM_ (putStrLn . unlines . convertEnum) . enumsFor (API "gl")) $ parseRegistry str
  when (PrintCommands `elem` opts) $ do
    putStrLn "---------------------------------------- commands"
    either putStrLn (mapM_ print . Map.elems . commands) $ parseRegistry str
  when (PrintCommandTypes `elem` opts) $ do
    putStrLn "---------------------------------------- command types"
    either putStrLn (mapM_ (putStrLn . showCommand) . Map.elems . commands) $ parseRegistry str

-- lookup' :: (Ord k, Show k) => k -> Map.Map k a -> a
-- lookup' k m = Map.findWithDefault (error ("unknown name " ++ show k)) k m

enumsFor :: API -> Registry -> [Enum']
enumsFor api r =
  [ e | es <- Map.elems (enums r)
  , e <- es
  , api `matches` enumAPI e ]

matches :: Eq a => a -> Maybe a -> Bool
_ `matches` Nothing = True
s `matches` Just t = s == t

convertEnum :: Enum' -> [String]
convertEnum e =
  [ n ++ " :: " ++ unTypeName (enumType e)
  , n ++ " = " ++ unEnumValue (enumValue e) ]
  where n = unEnumName . mangleEnumName . enumName $ e

mangleEnumName :: EnumName -> EnumName
mangleEnumName =
  EnumName . intercalate [splitChar] . headToLower . splitBy (== splitChar) . unEnumName
  where splitChar = '_'
        headToLower xs = map toLower (head xs) : tail xs

splitBy :: (a -> Bool) -> [a] -> [[a]]
splitBy _ [] = []
splitBy p xs = case break p xs of
                (ys, []  ) -> [ys]
                (ys, _:zs) -> ys : splitBy p zs

showCommand :: Command -> String
showCommand c =
  showString (signatureElementName (resultType c)) .
  showString "\n" .
  showString (concat (zipWith showParam ("::" : repeat "->") (paramTypes c))) .
  showString ("  " ++ (if null (paramTypes c) then "::" else "->") ++ " IO ") . showsPrec 11 (resultType c) . showString (showSignatureElement "" (resultType c)) .

  showString (signatureElementName (resultType c)) .
  showString " = undefined\n" $
  ""

showParam :: String -> SignatureElement -> String
showParam sep e = "  " ++ sep ++ " " ++ show e ++ showSignatureElement (inlineCode (signatureElementName e)) e

showSignatureElement :: String -> SignatureElement -> String
showSignatureElement name e
  | null comment = "\n"
  | otherwise = " -- ^ " ++ comment ++ ".\n"
  where comment =
          name ++
          maybe "" (\g -> " of type " ++ concat (replicate (numPointer e) "pointer to ") ++ inlineCode (unGroupName g)) (belongsToGroup e) ++
          maybe "" (\l -> " of length " ++ inlineCode l) (arrayLength e)

inlineCode :: String -> String
inlineCode s = "@" ++ s ++ "@"
