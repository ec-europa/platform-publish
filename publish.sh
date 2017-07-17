#!/bin/bash

# input :
#
# ${platform_version} : release branch or tag to sync
# ${deploy_repos} : list of git repositories to publish to
#
# output :
#
# FPFIS version of the platform pre-built and tagged in a git repo

set -e

# Computes a few required settings :
RELEASE=yes
MAJOR_VERSION="$(echo ${platform_version}|sed 's/release\///g'|awk -F. {'print $1"."$2'})"
RELEASE_BRANCH="release/${MAJOR_VERSION}" 

# if MAJOR_VERSION == platform_version, we updating the release branch (pre tag)
[ "${MAJOR_VERSION}" == "${platform_version}" ] && RELEASE=no

echo "Building platform version ${platform_version} for provisionning : "

# Try to checkout the tag first :

git clone -b ${MAJOR_VERSION} git@github.com:ec-europa/platform-deploy.git deploy || 
  # no tag deployed yet, checking out the release branch :
  git clone -b ${RELEASE_BRANCH} git@github.com:ec-europa/platform-deploy.git deploy || (
	  # Prepare new major release :
	  mkdir deploy
	  cd deploy
	  git init
	  git remote add origin git@github.com:ec-europa/platform-deploy.git
	  git checkout -b ${RELEASE_BRANCH}
)

# Refuse to create new tag if a newer tag exists ( to preserve release histoyr )
if [ "${RELEASE}" == "yes" ] && [ "$((echo ${platform_version};cd deploy;git tag)|grep ^${MAJOR_VERSION}|sort --version-sort|grep ${platform_version} -A1|grep -v ${platform_version}|wc -l)" -gt 1 ]; then
	echo "A newer tag has already been built and deployed, cannot rebuild it"
	exit 1
fi

# Make sure build is clean
[ -d build ] && rm -Rf build
mkdir build

# downloading dist :
if [ "${RELEASE}" == "yes" ]; then
  wget "http://platform-ci.ne-dev.eu/releases/platform-dev-${platform_version}.tar.gz" |tar -xzC build
else 
  wget "http://platform-ci.ne-dev.eu/releases/platform-dev-release-${MAJOR_VERSION}.tar.gz" |tar -xzC build
fi

# Sync files

rsync -rpKzl --delete-after --ignore-errors --force --exclude='sites/sites.php' --exclude="sites/settings.common.post.php" --exclude="sites/settings.common.php" --exclude="sites/all/modules/fpfis" --exclude=".git*" --exclude=".gitignore" "build/" "deploy/"

# Merge FPFIS conf and publish
(
	cd deploy
	git add . -A
	git commit -m"Published platform ${platform_version}"
	git fetch origin fpfis-conf/${MAJOR_VERSION} || (
		echo "[WARNING] No fpfis-conf/${MAJOR_VERSION} branch was found on the deploy repo"
		exit 1
	)
	git merge origin/fpfis-conf/${MAJOR_VERSION}
	git status
	if [ "${RELEASE}" == "yes" ]; then
		# Tagged, we add tje platform tag :
		git tag ${platform_version}|| (
			git tag -d ${platform_version}
			git tag ${platform_version}
		)
	fi
    for deploy_repo in ${deploy_repos}; do
      RANDOM_ORIGIN_NAME="random_${RANDOM}"
      echo "Deploying to ${deploy_repo}"
      git remote add ${RANDOM_ORIGIN_NAME} ${deploy_repo}
      git push ${RANDOM_ORIGIN_NAME} ${RELEASE_BRANCH}
      git push ${RANDOM_ORIGIN_NAME} --tags --force
    done
)
