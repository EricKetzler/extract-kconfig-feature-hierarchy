 #!/bin/bash

# Path to the directory containing the UVL and unconstrained feature files
UVL_DIR="./linux/kclause"
# Path to the linux source tree
LINUX_SRC_DIR="."

# Ensure you're in the Linux source directory
cd "$LINUX_SRC_DIR" || { echo "Linux source directory not found!"; exit 1; }

#remove old statistics and write new file
touch statistics.csv
echo "version;false negatives;false positives;tree depth;tree width;parent-child-relationships" > statistics.csv

# Loop through all .uvl files in the UVL directory
for uvl_file in "$UVL_DIR"/*[^hierarchy].uvl; do
    # Extract the version from the UVL filename (e.g., v2.6.24[x86].uvl -> v2.6.24)
    version=$(basename "$uvl_file" | sed -E 's/\[.*\]//; s/.uvl//')

    # Check out the corresponding Linux version using git
    git checkout -f "$version" || { echo "Failed to checkout version $version"; exit 1; }

    # Apply the Makefile patch
    wget -qO- https://raw.githubusercontent.com/ulfalizer/Kconfiglib/master/makefile.patch | patch -p1 || {
        echo "Failed to apply makefile patch"; exit 1;
    }
    echo "Makefile patch applied for version $version"

    # Extract the major version number (e.g., 2 from v2.6.24)
    major_version=$(echo "$version" | cut -d '.' -f 1 | sed 's/v//')

    # If the major version is 6, delete line 4 from kernel/module/Kconfig
    if [[ "$major_version" -eq 6 ]]; then
        KCONFIG_FILE="$LINUX_SRC_DIR/kernel/module/Kconfig"
        if [[ -f "$KCONFIG_FILE" ]]; then
            sed -i 's/modules//g' "$KCONFIG_FILE" || { echo "Failed to delete 'modules' from $KCONFIG_FILE"; exit 1; }
            echo "Deleted 'modules' from $KCONFIG_FILE for version $version"
        else
            echo "Kconfig file not found at $KCONFIG_FILE for version $version"
            exit 1
        fi
    else
        KCONFIG_FILE="$LINUX_SRC_DIR/init/Kconfig"
        if [[ -f "$KCONFIG_FILE" ]]; then
            sed -E -i 's/^\s*(option\s+)?modules\s*$//g' "$KCONFIG_FILE" || { echo "Failed to delete 'modules' from $KCONFIG_FILE"; exit 1; }
            echo "Deleted 'modules' from $KCONFIG_FILE for version $version"
        else
            echo "Kconfig file not found at $KCONFIG_FILE for version $version"
            exit 1
        fi
        sed -i  's/;//g' "drivers/hwmon/Kconfig"
        if [ "$version" = "v3.0" ]; then
            sed -i '1d' "drivers/staging/iio/light/Kconfig"
        fi
        if [ "$version" = "v3.10" ] || [ "$version" = "v3.11" ] || [ "$version" = "v3.7" ] || [ "$version" = "v3.8" ] || [ "$version" = "v3.9" ]; then
            sed -i '20d' "drivers/media/usb/stk1160/Kconfig"
        fi
        if [ "$version" = "v3.19" ]; then
            sed -i ':a;N;$!ba;s/\\\\\n\t\t//g' "sound/soc/intel/Kconfig"
        fi
        if [ "$version" = "v3.6" ] || [ "$version" = "v3.7" ] || [ "$version" = "v3.8" ] || [ "$version" = "v3.9" ]; then
            sed -i 's/+//' "sound/soc/ux500/Kconfig"
        fi
        if [ "$version" = "v4.18" ]; then
            sed -i 's/\xa0//g' "./net/netfilter/ipvs/Kconfig"
        fi
    fi

    # Call the Python script with the UVL file as an argument
    if [ "$major_version" -gt 3 ]; then
        make ARCH=x86 SRCARCH=x86 scriptconfig SCRIPT=construct-hierarchy.py SCRIPT_ARG="$uvl_file"
    else
        make -f ./scripts/kconfig/Makefile ARCH=x86 SRCARCH=x86 scriptconfig SCRIPT=construct-hierarchy.py SCRIPT_ARG="$uvl_file"
    fi

    # Undo changes before checking out the next branch
    git reset --hard

done
