# The small polish model runs on llama.cpp (MIT) — the same release the Mac app uses (b11155), built here for
# Android's CPU. Only the library is built: no tools, server, examples or tests.
cmake_minimum_required(VERSION 3.22.1)
project(evoollama LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

include(FetchContent)
FetchContent_Declare(llama
    GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
    GIT_TAG b11155
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(llama)

add_library(evoollama SHARED evoo_llama.cpp)
target_link_libraries(evoollama PRIVATE llama log)
# Android 15 phones may use 16 KB memory pages.
target_link_options(evoollama PRIVATE "-Wl,-z,max-page-size=16384")
