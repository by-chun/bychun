cmake_minimum_required(VERSION 3.22.1)
project(g_native LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)

include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/patch_keystone_python3.cmake)

# 内存工具（搜索/读写/指针/指令 patch）
add_library(memory SHARED native_memory.cpp)
# PTY 真交互终端
add_library(pty SHARED pty.cpp)

# gmem：以 root 身份执行的内存工具可执行文件。
add_executable(gmem gmem.cpp bp.cpp)
set_target_properties(gmem PROPERTIES POSITION_INDEPENDENT_CODE TRUE)

add_custom_command(TARGET gmem POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:gmem>
        ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libgmem.so
    COMMENT "copy gmem -> jniLibs/${ANDROID_ABI}/libgmem.so"
)

# ---------- Capstone（反汇编）----------
include(FetchContent)
set(CAPSTONE_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_CSTOOL OFF CACHE BOOL "" FORCE)
set(CAPSTONE_ARCHITECTURE_DEFAULT OFF CACHE BOOL "" FORCE)
set(CAPSTONE_ARM64_SUPPORT ON CACHE BOOL "" FORCE)
set(CAPSTONE_X86_SUPPORT OFF CACHE BOOL "" FORCE)
set(CAPSTONE_M680X_SUPPORT OFF CACHE BOOL "" FORCE)
set(CAPSTONE_EVM_SUPPORT OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    capstone
    GIT_REPOSITORY https://github.com/capstone-engine/capstone.git
    GIT_TAG 5.0.1
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(capstone)

add_library(disasm SHARED disasm.cpp)
target_link_libraries(disasm capstone)

# ---------- Keystone（汇编，仅 ARM/AArch64 目标，体积更小）----------
find_package(Python3 COMPONENTS Interpreter)
set(KEYSTONE_BUILD_STATIC_RUNTIME ON CACHE BOOL "" FORCE)
set(BUILD_LIBS_ONLY ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLVM_TARGETS_TO_BUILD "ARM;AArch64" CACHE STRING "" FORCE)
if(Python3_Interpreter_FOUND)
    set(PYTHON_EXECUTABLE "${Python3_EXECUTABLE}" CACHE FILEPATH "" FORCE)
endif()
FetchContent_Declare(
    keystone
    GIT_REPOSITORY https://github.com/keystone-engine/keystone.git
    GIT_TAG 0.9.2
    GIT_SHALLOW TRUE
)
FetchContent_GetProperties(keystone)
if(NOT keystone_POPULATED)
    FetchContent_Populate(keystone)
    patch_keystone_python3(${keystone_SOURCE_DIR})
    add_subdirectory(${keystone_SOURCE_DIR} ${keystone_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()

add_library(asm SHARED asm.cpp)
target_include_directories(asm PRIVATE
    ${keystone_SOURCE_DIR}/include
    ${keystone_BINARY_DIR}/include)
target_link_libraries(asm keystone)

find_library(log-lib log)
target_link_libraries(memory ${log-lib})
target_link_libraries(pty ${log-lib})
target_link_libraries(disasm ${log-lib})
target_link_libraries(asm ${log-lib})
