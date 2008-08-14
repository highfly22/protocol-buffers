module Text.ProtocolBuffers.Parser(pbParse,parseProto,filename1,filename2) where

import qualified Text.DescriptorProtos.DescriptorProto                as D(DescriptorProto)
import qualified Text.DescriptorProtos.DescriptorProto                as D.DescriptorProto(DescriptorProto(..))
import qualified Text.DescriptorProtos.DescriptorProto.ExtensionRange as D(ExtensionRange(ExtensionRange))
import qualified Text.DescriptorProtos.DescriptorProto.ExtensionRange as D.ExtensionRange(ExtensionRange(..))
import qualified Text.DescriptorProtos.EnumDescriptorProto            as D(EnumDescriptorProto)
import qualified Text.DescriptorProtos.EnumDescriptorProto            as D.EnumDescriptorProto(EnumDescriptorProto(..))
import qualified Text.DescriptorProtos.EnumValueDescriptorProto       as D(EnumValueDescriptorProto(EnumValueDescriptorProto))
import qualified Text.DescriptorProtos.EnumValueDescriptorProto       as D.EnumValueDescriptorProto(EnumValueDescriptorProto(..))
import qualified Text.DescriptorProtos.FieldDescriptorProto           as D(FieldDescriptorProto(FieldDescriptorProto))
import qualified Text.DescriptorProtos.FieldDescriptorProto           as D.FieldDescriptorProto(FieldDescriptorProto(..))
import qualified Text.DescriptorProtos.FieldDescriptorProto.Type      as D.FieldDescriptorProto(Type)
import           Text.DescriptorProtos.FieldDescriptorProto.Type      as D.FieldDescriptorProto.Type(Type(..))
import qualified Text.DescriptorProtos.FieldOptions                   as D(FieldOptions)
import qualified Text.DescriptorProtos.FieldOptions                   as D.FieldOptions(FieldOptions(..))
import qualified Text.DescriptorProtos.FileDescriptorProto            as D(FileDescriptorProto)
import qualified Text.DescriptorProtos.FileDescriptorProto            as D.FileDescriptorProto(FileDescriptorProto(..))
import qualified Text.DescriptorProtos.FileOptions                    as D.FileOptions(FileOptions(..))
import qualified Text.DescriptorProtos.MessageOptions                 as D.MessageOptions(MessageOptions(..))
import qualified Text.DescriptorProtos.MethodDescriptorProto          as D(MethodDescriptorProto(MethodDescriptorProto))
import qualified Text.DescriptorProtos.MethodDescriptorProto          as D.MethodDescriptorProto(MethodDescriptorProto(..))
import qualified Text.DescriptorProtos.ServiceDescriptorProto         as D.ServiceDescriptorProto(ServiceDescriptorProto(..))

import Text.ProtocolBuffers.Lexer(Lexed(..),alexScanTokens,getLinePos)
import Text.ProtocolBuffers.Header(ByteString,Int32,Int64,Word32,Word64
                                  ,mergeEmpty,ReflectEnum(reflectEnumInfo),enumName)
import Text.ProtocolBuffers.Instances(parseLabel,parseType)
import Control.Monad(when,liftM3)
import qualified Data.ByteString.Lazy.Char8 as LC(unpack,pack,notElem,head,readFile)
import Data.Char(isUpper)
import Data.Ix(inRange)
import Data.Sequence((|>))
import Text.ParserCombinators.Parsec(GenParser,ParseError,runParser,sourceName
                                    ,getInput,setInput,getPosition,setPosition,getState,setState
                                    ,(<?>),(<|>),option,token,choice,between,eof,unexpected)
import Text.ParserCombinators.Parsec.Pos(newPos)

type P = GenParser Lexed

pbParse :: String -> IO (Either ParseError D.FileDescriptorProto)
pbParse filename = fmap (parseProto filename) (LC.readFile filename)

parseProto :: String -> ByteString -> Either ParseError D.FileDescriptorProto
parseProto filename file = do
  let lexed = alexScanTokens file
      ipos = case lexed of
               [] -> setPosition (newPos filename 0 0)
               (l:_) -> setPosition (newPos filename (getLinePos l) 0)
  runParser (ipos >> parser) (initState filename) filename lexed

filename1,filename2 :: String
filename1 = "/tmp/unittest.proto"
filename2 = "/tmp/descriptor.proto"

initState :: String -> D.FileDescriptorProto
initState filename = mergeEmpty {D.FileDescriptorProto.name=Just (LC.pack filename)}

{-# INLINE mayRead #-}
mayRead :: ReadS a -> String -> Maybe a
mayRead f s = case f s of [(a,"")] -> Just a; _ -> Nothing

true,false :: ByteString
true = LC.pack "true"
false = LC.pack "false"

-- Use 'token' via 'tok' to make all the parsers for the Lexed values
tok :: (Lexed -> Maybe a) -> P s a
tok f = token show (\lexed -> newPos "" (getLinePos lexed) 0) f

pChar :: Char -> P s ()
pChar c = tok (\l-> case l of L _ x -> if (x==c) then return () else Nothing
                              _ -> Nothing) <?> ("character "++show c)

eol :: P s ()
eol = pChar ';'

pName :: ByteString -> P s ByteString
pName name = tok (\l-> case l of L_Name _ x -> if (x==name) then return x else Nothing
                                 _ -> Nothing) <?> ("name "++show (LC.unpack name))

strLit :: P s ByteString
strLit = tok (\l-> case l of L_String _ x -> return x
                             _ -> Nothing) <?> "quoted bytes or string literal"

intLit :: (Num a) => P s a
intLit = tok (\l-> case l of L_Integer _ x -> return (fromInteger x)
                             _ -> Nothing) <?> "integer literal"

fieldInt :: (Num a) => P s a
fieldInt = tok (\l-> case l of L_Integer _ x | inRange validRange x && not (inRange reservedRange x) -> return (fromInteger x)
                               _ -> Nothing) <?> "field number (from 0 to 2^29-1 and not in 19000 to 19999)"
  where validRange = (0,(2^(29::Int))-1)
        reservedRange = (19000,19999)

enumInt :: (Num a) => P s a
enumInt = tok (\l-> case l of L_Integer _ x | inRange validRange x -> return (fromInteger x)
                              _ -> Nothing) <?> "enum value (from 0 to 2^31-1)"
  where validRange = (0,(2^(31::Int))-1)

doubleLit :: P s Double
doubleLit = tok (\l-> case l of L_Double _ x -> return x
                                L_Integer _ x -> return (fromInteger x)
                                _ -> Nothing) <?> "double (or integer) literal"

ident,ident1,ident_package :: P s ByteString
ident = tok (\l-> case l of L_Name _ x -> return x
                            _ -> Nothing) <?> "identifier (perhaps dotted)"

ident1 = tok (\l-> case l of L_Name _ x | LC.notElem '.' x -> return x
                             _ -> Nothing) <?> "identifier (not dotted)"

ident_package = tok (\l-> case l of L_Name _ x | LC.head x /= '.' -> return x
                                    _ -> Nothing) <?> "package name (no leading dot)"

boolLit :: P s Bool
boolLit = tok (\l-> case l of L_Name _ x | x == true -> return True
                                         | x == false -> return False
                              _ -> Nothing) <?> "boolean literal ('true' or 'false')"

enumLit :: forall s a. (Read a,ReflectEnum a) => P s a -- This is very polymorphic, and with a good error message
enumLit = do
  s <- fmap' LC.unpack ident1
  case mayRead reads s of
    Just x -> return x
    Nothing -> let self = enumName (reflectEnumInfo (undefined :: a))
               in unexpected $ "Enum value not recognized: "++show s++", wanted enum value of type "++show self

-- subParser changes the user state. It is a bit of a hack and is used
-- to define an interesting style of parsing below.
subParser :: GenParser t sSub a -> sSub -> GenParser t s sSub
subParser doSub inSub = do
  in1 <- getInput
  pos1 <- getPosition
  let out = runParser (setPosition pos1 >> doSub >> getStatus) inSub (sourceName pos1) in1
  case out of Left pe -> fail ("the error message from the nested subParser was:\n"++indent (show pe))
              Right (outSub,in2,pos2) -> setInput in2 >> setPosition pos2 >> return outSub
 where getStatus = liftM3 (,,) getState getInput getPosition
       indent = unlines . map (\s -> ' ':' ':s) . lines

{-# INLINE return' #-}
return' :: (Monad m) => a -> m a
return' a = return $! a

{-# INLINE fmap' #-}
fmap' :: (Monad m) => (a->b) -> m a -> m b
fmap' f m = m >>= \a -> seq a (return $! (f a))

type Update s = (s -> s) -> P s ()
update' :: Update s
update' f = getState >>= \s -> setState $! (f s)

parser :: P D.FileDescriptorProto D.FileDescriptorProto 
parser = proto >> getState
  where proto = eof <|> (choice [ eol
                                , importFile
                                , package
                                , fileOption
                                , message upTopMsg
                                , enum upTopEnum
                                , extend upTopMsg upTopField
                                , service] >> proto)
        upTopMsg msg = update' (\s -> s {D.FileDescriptorProto.message_type=D.FileDescriptorProto.message_type s |> msg})
        upTopEnum e  = update' (\s -> s {D.FileDescriptorProto.enum_type=D.FileDescriptorProto.enum_type s |> e})
        upTopField f = update' (\s -> s {D.FileDescriptorProto.extension=D.FileDescriptorProto.extension s |> f})

importFile = pName (LC.pack "import") >> strLit >>= \p -> eol >> update' (\s -> s {D.FileDescriptorProto.dependency=(D.FileDescriptorProto.dependency s) |> p})

package = pName (LC.pack "package") >> ident_package >>= \p -> eol >> update' (\s -> s {D.FileDescriptorProto.package=Just p})

pOption :: P s String
pOption = pName (LC.pack "option") >> fmap LC.unpack ident1 >>= \optName -> pChar '=' >> return optName

fileOption = pOption >>= setOption >>= \p -> eol >> update' (\s -> s {D.FileDescriptorProto.options=Just p})
  where
    setOption optName = do
      old <- fmap (maybe mergeEmpty id . D.FileDescriptorProto.options) getState
      case optName of
        "java_package"         -> strLit >>= \p -> return' (old {D.FileOptions.java_package=Just p})
        "java_outer_classname" -> strLit >>= \p -> return' (old {D.FileOptions.java_outer_classname=Just p})
        "java_multiple_files"  -> boolLit >>= \p -> return' (old {D.FileOptions.java_multiple_files=Just p})
        "optimize_for"         -> enumLit >>= \p -> return' (old {D.FileOptions.optimize_for=Just p})
        s -> unexpected $ "option name "++s

message :: (D.DescriptorProto -> P s ()) -> P s ()
message up = pName (LC.pack "message") >> do
  self <- ident1
  up =<< subParser (pChar '{' >> subMessage) (mergeEmpty {D.DescriptorProto.name=Just self})

-- subMessage is also used to parse group declarations
subMessage = (pChar '}') <|> (choice [ eol 
                                     , field upNestedMsg Nothing >>= upMsgField
                                     , message upNestedMsg
                                     , enum upNestedEnum
                                     , extensions
                                     , extend upNestedMsg upMsgField
                                     , messageOption] >> subMessage)
  where upNestedMsg msg = update' (\s -> s {D.DescriptorProto.nested_type=D.DescriptorProto.nested_type s |> msg})
        upNestedEnum e  = update' (\s -> s {D.DescriptorProto.enum_type=D.DescriptorProto.enum_type s |> e})
        upMsgField f    = update' (\s -> s {D.DescriptorProto.field=D.DescriptorProto.field s |> f})

messageOption = pOption >>= setOption >>= \p -> eol >> update' (\s -> s {D.DescriptorProto.options=Just p}) 
  where
    setOption optName = do
      old <- fmap (maybe mergeEmpty id . D.DescriptorProto.options) getState
      case optName of
        "message_set_wire_format" -> boolLit >>= \p -> return' (old {D.MessageOptions.message_set_wire_format=Just p})
        s -> unexpected $ "option name "++s

extend :: (D.DescriptorProto -> P s ()) -> (D.FieldDescriptorProto -> P s ())
       -> P s ()
extend upGroup upField = pName (LC.pack "extend") >> do
  typeExtendee <- ident
  let first = (eol >> first) <|> ((field upGroup (Just typeExtendee) >>= upField) >> rest)
      rest = pChar '}' <|> ((eol <|> (field upGroup (Just typeExtendee) >>= upField)) >> rest)
  pChar '{' >> first
  
field :: (D.DescriptorProto -> P s ()) -> Maybe ByteString
      -> P s D.FieldDescriptorProto
field upGroup maybeExtendee = do 
  sLabel <- choice . map (pName . LC.pack) $ ["optional","repeated","required"]
  theLabel <- maybe (fail ("not a valid Label :"++show sLabel)) return (parseLabel (LC.unpack sLabel))
  sType <- ident
  let (maybeTypeCode,maybeTypeName) = case parseType (LC.unpack sType) of
                                        Just t -> (Just t,Nothing)
                                        Nothing -> (Nothing, Just sType)
  name <- ident1
  number <- pChar '=' >> fieldInt
  (maybeOptions,maybeDefault) <-
    if maybeTypeCode == Just TYPE_GROUP
      then do when (not (isUpper (LC.head name)))
                   (fail $ "Group names must start with an upper case letter: "++show name)
              upGroup =<< subParser (pChar '{' >> subMessage) (mergeEmpty {D.DescriptorProto.name=Just name})
              return (Nothing,Nothing)
      else do hasBracket <- option False (pChar '[' >> return True)
              pair <- if not hasBracket then return (Nothing,Nothing)
                        else subParser (subBracketOptions maybeTypeCode) (Nothing,Nothing)
              eol
              return pair
  return $ D.FieldDescriptorProto
               { D.FieldDescriptorProto.name = Just name
               , D.FieldDescriptorProto.number = Just number
               , D.FieldDescriptorProto.label = Just theLabel
               , D.FieldDescriptorProto.type' = maybeTypeCode
               , D.FieldDescriptorProto.type_name = maybeTypeName
               , D.FieldDescriptorProto.extendee = maybeExtendee
               , D.FieldDescriptorProto.default_value = maybeDefault
               , D.FieldDescriptorProto.options = maybeOptions
               }

subBracketOptions :: Maybe Type
                  -> P (Maybe D.FieldOptions, Maybe ByteString) ()
subBracketOptions mt = (defaultConstant <|> fieldOptions) >> (pChar ']' <|> (pChar ',' >> subBracketOptions mt))
  where defaultConstant = do
          pName (LC.pack "default")
          x <- pChar '=' >> constant mt
          (a,_) <- getState
          setState $! (a,Just x)
        fieldOptions = do
          optName <- fmap LC.unpack ident1
          pChar '='
          (mOld,def) <- getState
          let old = maybe mergeEmpty id mOld
          case optName of
            "ctype" | (Just TYPE_STRING) == mt -> do
              enumLit >>= \p -> let new = old {D.FieldOptions.ctype=Just p}
                                in seq new $ setState $! (Just new,def)
            "experimental_map_key" | Nothing == mt -> do
              strLit >>= \p -> let new = old {D.FieldOptions.experimental_map_key=Just p}
                               in seq new $ setState $! (Just new,def)
            s -> unexpected $ "option name: "++s

-- This does a type and range safe parsing of the default value,
-- except for enum constants which cannot be checked (the definition
-- may not have been parsed yet).
--
-- Double and Float are checked to be not-Nan and not-Inf.  The
-- int-like types are checked to be within the corresponding range.
constant :: Maybe Type -> P s ByteString
constant Nothing = ident1 -- hopefully a matching enum
constant (Just t) =
  case t of
    TYPE_DOUBLE  -> do d <- doubleLit
                       when (isNaN d || isInfinite d)
                            (fail $ "Floating point literal "++show d++" is out of range for type "++show t)
                       return' (LC.pack . show $ d)
    TYPE_FLOAT   -> do d <- doubleLit
                       let fl :: Float
                           fl = read (show d)
                       when (isNaN fl || isInfinite fl || (d==0) /= (fl==0))
                            (fail $ "Floating point literal "++show d++" is out of range for type "++show t)
                       return' (LC.pack . show $ d)
    TYPE_BOOL    -> boolLit >>= \b -> return' $ if b then true else false
    TYPE_STRING  -> strLit
    TYPE_BYTES   -> strLit
    TYPE_GROUP   -> unexpected $ "cannot have a constant literal for type "++show t
    TYPE_MESSAGE -> unexpected $ "cannot have a constant literal for type "++show t
    TYPE_ENUM    -> ident1 -- IMPOSSIBLE : SHOULD HAVE HAD Maybe Type PARAMETER match Nothing
    TYPE_SFIXED32 -> f (undefined :: Int32)
    TYPE_SINT32   -> f (undefined :: Int32)
    TYPE_INT32    -> f (undefined :: Int32)
    TYPE_SFIXED64 -> f (undefined :: Int64)
    TYPE_SINT64   -> f (undefined :: Int64)
    TYPE_INT64    -> f (undefined :: Int64)
    TYPE_FIXED32  -> f (undefined :: Word32)
    TYPE_UINT32   -> f (undefined :: Word32)
    TYPE_FIXED64  -> f (undefined :: Word64)
    TYPE_UINT64   -> f (undefined :: Word64)
  where f :: (Bounded a,Integral a) => a -> P s ByteString
        f u = do let range = (toInteger (minBound `asTypeOf` u),toInteger (maxBound `asTypeOf` u))
                 i <- intLit
                 when (not (inRange range i))
                      (fail $ "default value "++show i++" is out of range for type "++show t)
                 return' (LC.pack . show $ i)

enum :: (D.EnumDescriptorProto -> P s ()) -> P s ()
enum up = pName (LC.pack "enum") >> do
  self <- ident1
  up =<< subParser (pChar '{' >> subEnum) (mergeEmpty {D.EnumDescriptorProto.name=Just self})

subEnum = (pChar '}') <|> ((eol <|> enumVal <|> (pOption >>= setOption)) >> subEnum)
  where setOption = fail "There are no options for enumerations (when this parser was written)"
        enumVal :: P D.EnumDescriptorProto ()
        enumVal = do
          name <- ident1
          number <- pChar '=' >> enumInt
          eol
          let v = D.EnumValueDescriptorProto
                       { D.EnumValueDescriptorProto.name = Just name
                       , D.EnumValueDescriptorProto.number = Just number
                       , D.EnumValueDescriptorProto.options = Nothing
                       }
          update' (\s -> s {D.EnumDescriptorProto.value=D.EnumDescriptorProto.value s |> v})

extensions = pName (LC.pack "extensions") >> do
  start <- fmap Just fieldInt
  pName (LC.pack "to")
  end <- (fmap Just fieldInt <|> fmap (const Nothing) (pName (LC.pack "max")))
  let e = D.ExtensionRange
            { D.ExtensionRange.start = start
            , D.ExtensionRange.end = end
            }
  update' (\s -> s {D.DescriptorProto.extension_range=D.DescriptorProto.extension_range s |> e})

service = pName (LC.pack "service") >> do
  name <- ident1
  f <- subParser (pChar '{' >> subRpc) (mergeEmpty {D.ServiceDescriptorProto.name=Just name})
  update' (\s -> s {D.FileDescriptorProto.service=D.FileDescriptorProto.service s |> f})
       
 where subRpc = pChar '}' <|> ((eol <|> rpc <|> (pOption >>= setOption)) >> subRpc)
       rpc = pName (LC.pack "rpc") >> do
               name <- ident1
               input <- between (pChar '(') (pChar ')') ident1
               pName (LC.pack "returns")
               output <- between (pChar '(') (pChar ')') ident1
               eol
               let m = D.MethodDescriptorProto
                         { D.MethodDescriptorProto.name=Just name
                         , D.MethodDescriptorProto.input_type=Just input
                         , D.MethodDescriptorProto.output_type=Just output
                         , D.MethodDescriptorProto.options=Nothing
                         }
               update' (\s -> s {D.ServiceDescriptorProto.method=D.ServiceDescriptorProto.method s |> m})
       setOption = fail "There are no options for services (when this parser was written)"