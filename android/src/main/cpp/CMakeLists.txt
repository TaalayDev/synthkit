cmake_minimum_required(VERSION 3.22.1)

project(synthkit_android LANGUAGES CXX)

add_library(
  synthkit_android
  SHARED
  synthkit_android_ffi.cpp
)

target_compile_features(synthkit_android PRIVATE cxx_std_17)

find_library(log-lib log)

target_link_libraries(
  synthkit_android
  ${log-lib}
)
