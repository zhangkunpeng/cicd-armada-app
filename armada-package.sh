

APP_NAME="stx-cicd"
APP_VERSION="1.0.0"
TAR_FLAGS=-zcvf

function build_application_tarball {
    local manifest=$1
    manifest_file=$(basename ${manifest})
    manifest_name=${manifest_file%.yaml}
    deprecated_tarball_name="helm-charts-${manifest_name}"
    build_image_versions_to_manifest ${manifest}

    cp ${manifest} staging/.
    if [ $? -ne 0 ]; then
        echo "Failed to copy the manifests to ${BUILD_OUTPUT_PATH}/staging" >&2
        exit 1
    fi
    cp stx-cicd-helm/files/* staging/.
    cd staging
    # Add metadata file
    touch metadata.yaml
    echo "app_name: ${APP_NAME}" >> metadata.yaml
    echo "app_version: ${APP_VERSION}" >> metadata.yaml
    if [ -n "${PATCH_DEPENDENCIES}" ]; then
        echo "patch_dependencies:" >> metadata.yaml
        for patch in ${PATCH_DEPENDENCIES[@]}; do
            echo "  - ${patch}" >> metadata.yaml
        done
    fi

    # Add an md5
    find . -type f ! -name '*.md5' -print0 | xargs -0 md5sum > checksum.md5

    cd ..
    tarball_name="${APP_NAME}-${APP_VERSION}.tgz"
    tar ${TAR_FLAGS} ${tarball_name} -C staging/ .
    if [ $? -ne 0 ]; then
        echo "Failed to create the tarball" >&2
        exit 1
    fi

    #rm staging/${manifest_file}
    #rm staging/checksum.md5
    echo "    ${BUILD_OUTPUT_PATH}/${tarball_name}"
}

function parse_yaml {
    # Create a new yaml file based on sequentially merging a list of given yaml files
    local yaml_script="
import sys
import yaml

yaml_files = sys.argv[2:]
yaml_output = sys.argv[1]

def merge_yaml(yaml_old, yaml_new):
    merged_dict = {}
    merged_dict = yaml_old.copy()
    for k in yaml_new.keys():
        if not isinstance(yaml_new[k], dict):
            merged_dict[k] = yaml_new[k]
        elif k not in yaml_old:
            merged_dict[k] = merge_yaml({}, yaml_new[k])
        else:
            merged_dict[k] = merge_yaml(yaml_old[k], yaml_new[k])
    return merged_dict

yaml_out = {}
for yaml_file in yaml_files:
    for document in yaml.load_all(open(yaml_file)):
        document_name = (document['schema'], document['metadata']['schema'], document['metadata']['name'])
        yaml_out[document_name] = merge_yaml(yaml_out.get(document_name, {}), document)
yaml.dump_all(yaml_out.values(), open(yaml_output, 'w'), default_flow_style=False)
    "
    python -c "${yaml_script}" ${@}
}

# Create a new tarball containing all the contents we extracted
# tgz files under helm are relocated to subdir charts.
# Files under armada are left at the top level
rm -rf staging
mkdir -p staging
if [ $? -ne 0 ]; then
    echo "Failed to create ${BUILD_OUTPUT_PATH}/staging" >&2
    exit 1
fi

# Stage all the charts
cp -R stx-cicd-helm/charts staging/charts
if [ $? -ne 0 ]; then
    echo "Failed to copy the charts from ${BUILD_OUTPUT_PATH}/usr/lib/helm to ${BUILD_OUTPUT_PATH}/staging/charts" >&2
    exit 1
fi

# Merge yaml files:
APP_YAML=${APP_NAME}.yaml
parse_yaml $APP_YAML `ls -rt stx-cicd-helm/manifasts/*.yaml`

echo "Results:"
# Build tarballs for merged yaml
build_application_tarball $APP_YAML

exit 0