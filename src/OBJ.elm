module OBJ exposing (..)

{-|


# .obj file loader

The returned models can be rendered using `indexedTriangles` from `WebGL`.

    WebGL.indexedTriangles mesh.vertices mesh.indices


## From URL

All these methods take an URL as the first parameter.


### Single model

Use the methods from here if you know whats in your file
and if they only contain a single object with a single material.
These are just provided for convenience.

@docs loadMeshWithoutTexture, loadMesh, loadMeshWithTangent


### General

Use these methods if you don't know what kind of files you'll get or
if your files contain multiple groups or materials.

@docs loadObjFile, loadObjFileWith, Settings, defaultSettings


## From String

@docs parseObjStringWith

-}

import Dict exposing (Dict)
import Http
import OBJ.Assembler exposing (compile)
import OBJ.Parser exposing (parse, startParse, stepParse, Progress(..))
import OBJ.Types exposing (Mesh, ObjFile)
import Task exposing (Task)
import Process


--

import OBJ.Assembler exposing (compile)
import OBJ.Parser exposing (parse)
import OBJ.Types exposing (..)
import OBJ.InternalTypes exposing (log)


{-| Load a model that doesn't have texture coordinates.
-}
loadMeshWithoutTexture : String -> (Result String (MeshWith Vertex) -> msg) -> Cmd msg
loadMeshWithoutTexture url msg =
    loadObjFile url
        (\res ->
            case res of
                Ok f ->
                    case (Dict.values f |> List.map Dict.values) of
                        [ [ WithoutTexture m ] ] ->
                            msg (Ok m)

                        _ ->
                            msg (Err "file loaded correctely, but there were more than one model.")

                Err e ->
                    msg (Err e)
        )


{-| Load a model with texture coordinates.
-}
loadMesh : String -> (Result String (MeshWith VertexWithTexture) -> msg) -> Cmd msg
loadMesh url msg =
    loadObjFile url
        (\res ->
            case res of
                Ok f ->
                    case (Dict.values f |> List.map Dict.values) of
                        [ [ WithTexture m ] ] ->
                            msg (Ok m)

                        _ ->
                            msg (Err "file loaded correctely, but there were more than one model.")

                Err e ->
                    msg (Err e)
        )


{-| Load a model with texture coordinate and calculate vertex tangents.
This is needed if you want to do tangent space normal mapping.
-}
loadMeshWithTangent : String -> (Result String (MeshWith VertexWithTextureAndTangent) -> msg) -> Cmd msg
loadMeshWithTangent url msg =
    loadObjFile url
        (\res ->
            case res of
                Ok f ->
                    case (Dict.values f |> List.map Dict.values) of
                        [ [ WithTextureAndTangent m ] ] ->
                            msg (Ok m)

                        _ ->
                            msg (Err "file loaded correctely, but there were more than one model.")

                Err e ->
                    msg (Err e)
        )


{-| Load a .obj file from an URL

    loadObjFile url ObjFileLoaded

-}
loadObjFile : String -> (Result String ObjFile -> msg) -> Cmd msg
loadObjFile =
    loadObjFileWith defaultSettings


{-| withTangents : If true, vertex tangents will be calculated for meshes with texture coordinates.
This is needed if you want to do tangent space normal mapping.
-}
type alias Settings =
    { withTangents : Bool }


{-| -}
defaultSettings : Settings
defaultSettings =
    { withTangents = False }


{-| -}
loadObjFileWith : Settings -> String -> (Result String ObjFile -> msg) -> Cmd msg
loadObjFileWith settings url msg =
    Http.toTask (Http.getString url)
        |> Task.andThen
            (\s ->
                nonBlockingParse settings s
             -- parseObjStringWith settings s |> Task.succeed
            )
        |> Task.onError (\e -> Task.succeed (Err ("failed to load:\n" ++ toString e)))
        |> Task.attempt
            (\r ->
                case r of
                    Ok (Ok m) ->
                        msg (Ok m)

                    Ok (Err e) ->
                        msg (Err e)

                    Err e ->
                        msg (Err e)
            )


{-| Same as `loadObjFile`, but works on a string.
This is a blocking (!) operation.
If your string is big, your browser will freeze.
`loadObjFile` is non-blocking.
-}
parseObjStringWith : Settings -> String -> Result String ObjFile
parseObjStringWith config input =
    parse input
        |> Result.map (compile config)


nonBlockingParse : Settings -> String -> Task x (Result String ObjFile)
nonBlockingParse settings input =
    nonBlockingParseHelper settings (startParse input)


nonBlockingParseHelper : Settings -> Progress -> Task x (Result String ObjFile)
nonBlockingParseHelper settings p =
    Process.sleep 0
        |> Task.andThen
            (\_ ->
                case stepParse 100 p of
                    InProgress p_ ->
                        nonBlockingParseHelper settings (InProgress p_)

                    Finished d ->
                        Result.map (compile settings) d
                            |> Task.succeed
            )
