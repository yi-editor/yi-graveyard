{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_HADDOCK show-extensions #-}

-- |
-- Module      :  Yi.Config.Users.Michal
-- License     :  GPL-2
-- Maintainer  :  yi-devel@googlegroups.com
-- Stability   :  experimental
-- Portability :  portable

module Yi.Config.Users.Michal where

import           Data.Bool
import           Data.Eq
import           Data.Function
import           Data.List (isPrefixOf, isSuffixOf)
import           Data.Monoid ((<>))
import qualified Data.Text as T
import           Data.Time.Clock (getCurrentTime)
import           Data.Time.Format (formatTime)
import           Prelude (String, take, length, repeat, fmap, IO, Monad(..), (>>))
import           System.FilePath (takeFileName)
import           System.Locale (defaultTimeLocale)
import           Yi hiding (super)
import qualified Yi.Keymap.Vim as V2
import qualified Yi.Keymap.Vim.Common as V2
import qualified Yi.Keymap.Vim.Utils as V2
import qualified Yi.Rope as R
import qualified Yi.Style (Color(Default))

myConfig :: Config
myConfig = defaultVimConfig {
    modeTable = myModes <> fmap (onMode prefIndent) (modeTable defaultVimConfig),
    defaultKm = myKeymapSet,
    configCheckExternalChangesObsessively = False,
    configUI = (configUI defaultVimConfig)
     {
       configTheme = myTheme,
       configWindowFill = '~'    -- Typical for Vim
     }
}

defaultSearchKeymap :: Keymap
defaultSearchKeymap = do
  Event (KASCII c) [] <- anyEvent
  write . isearchAddE $ T.singleton c

myKeymapSet :: KeymapSet
myKeymapSet = V2.mkKeymapSet $ V2.defVimConfig `override` \super this ->
    let eval = V2.pureEval this
    in super {
          -- Here we can add custom bindings.
          -- See Yi.Keymap.Vim.Common for datatypes and
          -- Yi.Keymap.Vim.Utils for useful functions like mkStringBindingE

          -- In case of conflict, that is if there exist multiple bindings
          -- whose prereq function returns WholeMatch,
          -- the first such binding is used.
          -- So it's important to have custom bindings first.
          V2.vimBindings = myBindings eval <> V2.vimBindings super
        }

myBindings :: (V2.EventString -> EditorM ()) -> [V2.VimBinding]
myBindings eval =
    let nmap  x y = V2.mkStringBindingE V2.Normal V2.Drop (x, y, id)
        imap  x y = V2.VimBindingE (\evs state -> case V2.vsMode state of
                                    V2.Insert _ ->
                                        fmap (const (y >> return V2.Continue))
                                             (evs `V2.matchesString` x)
                                    _ -> V2.NoMatch)
        nmap'  x y = V2.mkStringBindingY V2.Normal (x, y, id)
    in [
         -- Tab traversal
         nmap  "<C-h>" previousTabE
       , nmap  "<C-l>" nextTabE
       , nmap  "<C-l>" nextTabE

         -- Press space to clear incremental search highlight
       , nmap  " " (eval ":nohlsearch<CR>")

         -- for times when you don't press shift hard enough
       , nmap  ";" (eval ":")

       , nmap  "<F3>" (withCurrentBuffer deleteTrailingSpaceB)
       , nmap  "<F4>" (withCurrentBuffer moveToSol)
       , nmap  "<F1>" (withCurrentBuffer readCurrentWordB >>= printMsg . R.toText)

       , imap  "<Home>" (withCurrentBuffer moveToSol)
       , imap  "<End>"  (withCurrentBuffer moveToEol)
       , nmap' "<F12>"  insertCurrentDate
       ]

-- | I declare "proper black" in GTK, since Vty terminal seems to have grayish black in 16-color system.
--   Fortunately default _background_ color is available through Default :: Yi.Style.Color.
--   Note that this works only in background! (Default foreground color is green.)
defaultColor :: Yi.Style.Color
defaultColor = Yi.Style.Default

-- This is based on Vim's ':colorscheme murphy', but with gray strings, and more brown on operators.
myTheme :: Proto UIStyle
myTheme = defaultTheme `override` \super _ -> super
  { modelineAttributes   = emptyAttributes { foreground = black,   background = darkcyan }
  , tabBarAttributes     = emptyAttributes { foreground = white,   background = defaultColor }
  , baseAttributes       = emptyAttributes { foreground = defaultColor, background = defaultColor, bold=True }
  , commentStyle         = withFg darkred <> withBd False <> withItlc True
--  , selectedStyle        = withFg black   <> withBg green <> withReverse True
  , selectedStyle        = withReverse True
  , errorStyle           = withBg red     <> withFg white
  , operatorStyle        = withFg brown   <> withBd False
  , hintStyle            = withBg brown   <> withFg black
  , importStyle          = withFg blue
  , dataConstructorStyle = withFg blue
  , typeStyle            = withFg blue
  , keywordStyle         = withFg yellow
  , builtinStyle         = withFg brown
  , strongHintStyle      = withBg brown   <> withUnderline True
  , stringStyle          = withFg brown   <> withBd False
  , preprocessorStyle    = withFg blue
--  , constantStyle      = withFg cyan
--  , specialStyle      = withFg yellow
  }

-- Softtabs of 2 characters for Berkeley coding style, if not editing makefile.
prefIndent :: Mode syntax -> Mode syntax
prefIndent m = if modeName m == "Makefile"
                 then m
                 else m {
        modeIndentSettings = IndentSettings
            {
                expandTabs = True,
                shiftWidth = 2,
                tabSize    = 2
            }
        }

myModes :: [AnyMode]
myModes = [diaryMode]

-- inserting current date and underline
currentDate :: IO String
currentDate =
    do tim <- Data.Time.Clock.getCurrentTime
       return $ formatTime locale  "%A %b %e %Y" tim
  where locale = System.Locale.defaultTimeLocale

makeUnderline :: String -> String
makeUnderline s = s <> ('\n' : line) <> "\n"
  where
    line = take (length s) (repeat '=')

currentDateAndUnderline :: IO String
currentDateAndUnderline =
    do d <- currentDate
       return $ makeUnderline d

insertCurrentDate :: YiM ()
insertCurrentDate =
  withUI (\_ -> currentDateAndUnderline) >>= withCurrentBuffer . insertN . R.fromString

-- NOTE: use fundamentalMode as a base?
diaryMode :: AnyMode
diaryMode = AnyMode $ (\super -> super { modeApplies = \path _contents -> let name = takeFileName path
                                                                in ".txt" `isSuffixOf`  name &&
                                                                   "diary" `isPrefixOf` name,
                               modeName    = "Diary",
                               modeOnLoad  = do modeOnLoad super
                                                r:_ <- regexB Forward $ makeSimpleSearch "*** TODAY ***"
                                                moveTo . regionStart $ r
                             }) $ emptyMode
