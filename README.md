# STCLang: A library for implicit, monadic dataflow parallelism



To make this work, please change the `extra-lib-dirs` path in `statefulness.cabal` accordingly.


(Currently, the streams-based version does not work with the development setup (GHC 8.2.2) of the project.
 This is due to problems with type resolution. It is therefore necessary to change the GHC version if the
 streams-based version is used in other code!)
