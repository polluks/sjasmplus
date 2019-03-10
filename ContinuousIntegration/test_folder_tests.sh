#!/bin/bash

## script init + helper functions
shopt -s globstar nullglob
HELP_STRING="Run the script from \033[96mproject root\033[0m directory."
HELP_STRING+="\nYou can provide one argument to specify particular sub-directory in \033[96mtests\033[0m directory, example:"
HELP_STRING+="\n  $ \033[96mContinuousIntegration/test_folder_tests.sh z80/\033[0m \t\t# to run only tests from \033[96mtests/z80/\033[0m directory"
HELP_STRING+="\nIf partial file name is provided, it'll be searched for (but file names with space break it,\033[1m it's not 100% functional\033[0m):"
HELP_STRING+="\n  $ \033[96mContinuousIntegration/test_folder_tests.sh z8\033[0m \t\t# to run tests from \033[96mtests/z80/\033[0m and \033[96mtests/z80n/\033[0m directories"
PROJECT_DIR=$PWD
BUILD_DIR="$PROJECT_DIR/build/tests"
exitCode=0
totalTests=0        # +1 per ASM
totalChecks=0       # +1 per diff/check

# verify the directory structure is set up as expected and the working directory is project root
[[ ! -f "${PROJECT_DIR}/ContinuousIntegration/test_folder_tests.sh" ]] && echo -e "\033[91munexpected working directory\033[0m\n$HELP_STRING" && exit 1

# seek for files to be processed (either provided by user argument, or default tests/ dir)
if [[ $# -gt 0 ]]; then
    [[ "-h" == "$1" || "--help" == "$1" ]] && echo -e $HELP_STRING && exit 0
    TEST_FILES=("${PROJECT_DIR}/tests/$1"**/*.asm)
else
    echo -e "Searching directory \033[96m${PROJECT_DIR}/tests/\033[0m for '.asm' files..."
    TEST_FILES=("${PROJECT_DIR}/tests/"**/*.asm)  # try default test dir
fi
# check if some files were found, print help message if search failed
[[ -z $TEST_FILES ]] && echo -e "\033[91mno files found\033[0m\n$HELP_STRING" && exit 1

## create temporary build directory for output
echo -e "Creating temporary \033[96m$BUILD_DIR\033[0m directory..."
rm -rf "$BUILD_DIR"
# terminate in case the create+cd will fail, this is vital
mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR" || exit 1

## go through all asm files in tests directory and verify results
for f in "${TEST_FILES[@]}"; do
    ## ignore directories themselves (which have "*.asm" name)
    [[ -d $f ]] && continue
    ## ignore "include" files (must have ".i.asm" extension)
    [[ ".i.asm" == ${f:(-6)} ]] && continue
    ## standalone .asm file was found, try to build it
    rm -rf *        # clear the temporary build directory
    totalTests=$((totalTests + 1))
    # set up various "test-name" variables for file operations
    src_dir=`dirname "$f"`          # source directory (dst_dir is "." = "build/tests")
    file_asm=`basename "$f"`        # just "file.asm" name
    src_base="${f%.asm}"            # source directory + base ("src_dir/file"), to add extensions
    dst_base="${file_asm%.asm}"     # local-directory base (just "file" basically), to add extensions
    # copy "src_dir/basename*.(asm|lua)" file(s) into working directory
    for subf in "$src_base"*.{asm,lua}; do
        [[ -d "$subf" ]] && continue
        cp "$subf" ".${subf#$src_dir}"
    done
    # copy "src_dir/basename*" sub-directories into working directory (ALL files in them)
    for subf in "$src_base"*; do
        [[ ! -d "$subf" ]] && continue
        cp -r "$subf" ".${subf#$src_dir}"
    done
    # see if there are extra options defined (and read them into array)
    options=()
    [[ -s "${src_base}.options" ]] && options=(`cat "${src_base}.options"`)
    # check if .lst file is required to verify the test, set up options to produce one
    [[ -s "${src_base}.lst" ]] && options+=("--lst=${dst_base}.lst") && options+=('--lstlab')
    ## built it with sjasmplus (remember exit code)
    echo -e "\033[95mAssembling\033[0m file \033[96m${file_asm}\033[0m in test \033[96m${src_dir}\033[0m, options [\033[96m${options[@]}\033[0m]"
    totalChecks=$((totalChecks + 1))    # assembling is one check
    ${PROJECT_DIR}/sjasmplus --nologo --msg=none --fullpath "${options[@]}" "$file_asm"
    last_result=$?
    last_result_origin="sjasmplus"
    ## validate results
    # LST file overrides assembling exit code (new exit code is from diff between lst files)
    if [[ -s "${src_base}.lst" ]]; then
        diff --strip-trailing-cr "${src_base}.lst" "${dst_base}.lst"
        last_result=$?
        last_result_origin="diff"
    fi
    # report assembling exit code problem here (ahead of binary result tests)
    if [[ $last_result -ne 0 ]]; then
        echo -e "\033[91mError status $last_result returned by $last_result_origin\033[0m"
        exitCode=$((exitCode + 1))
    else
        echo -e "\033[92mOK: assembling or listing\033[0m"
    fi
    # check binary results, if TAP or BIN are present in source directory
    for binext in {'tap','bin'}; do
        if [[ -f "${src_base}.${binext}" ]]; then
            upExt=`echo $binext | tr '[:lower:]' '[:upper:]'`
            totalChecks=$((totalChecks + 1))        # +1 for each binary check
            echo -n -e "\033[91m"
            ! diff "${src_base}.${binext}" "${dst_base}.${binext}" \
                && exitCode=$((exitCode + 1)) \
                || echo -e "\033[92mOK: $upExt is identical\033[0m"
            echo -n -e "\033[0m"
        fi
    done
    #read -p "press..."      # DEBUG helper to examine produced files
done # end of FOR (go through all asm files)
# display OK message if no error was detected
[[ $exitCode -eq 0 ]] \
    && echo -e "\033[92mFINISHED: OK, $totalChecks checks passed ($totalTests tests) \033[91m■\033[93m■\033[32m■\033[96m■\033[0m" \
    && exit 0
# display error summary and exit with error code
echo -e "\033[91mFINISHED: $exitCode/$totalChecks checks failed ($totalTests tests) \033[91m■\033[93m■\033[32m■\033[96m■\033[0m"
exit $exitCode
