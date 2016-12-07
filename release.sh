#!/bin/sh

#  release.sh
#
#
#  Created by Maxim Konovalov on 19.08.14.
#
# TODO:
# 1. Refactor with functions

#if ($1 = "-help")
#then
#echo "usage: release.sh [-ignore-snapshots] [-skip-tests] [-username <login>] [-password <passwd>]"
#fi

echo "Working dir: $(pwd)"
echo "PATH: $PATH"
headBranchShortName="master"
echo "Available gems list:"
gem list

#git config user.name "Bamboo"
#git config user.email "konovalov@bpcbt.com"

#exit 1
createBranch=false
prepareRelease=false
fixMavenTags=false
deploy=false
startCommit=HEAD

while [[ $# > 0 ]]
do
key="$1"
shift


if [ $key == "-ignore-snapshots" ]
then
ignoreSnapshots=true
echo "Ignoring SNAPSHOT dependencies"
fi

if [ $key == "-skip-tests" ]
then
skipTests=true
echo "Tests will be skipped"
fi


if [[ $key =~ ^-profile=.* ]]
then
profile=${key##*=}
echo "Profile will be used: $profile"
fi

if [[ $key =~ ^-username=.* ]]
then
username=${key##*=}
#echo "Username: $username"
fi

if [[ $key =~ ^-password=.* ]]
then
password=${key##*=}
#echo "Password: $password"
fi

if [[ $key =~ ^-start-branch=.* ]]
then
headBranchShortName=${key##*=}
fi

if [[ $key =~ ^-goals=.* ]]
then
goals=${key##*=}
echo "goals: $goals"
if [[ ${goals} =~ ^.*branch.* ]]; then createBranch=true; fi
if [[ ${goals} =~ ^.*prepare.* ]]; then prepareRelease=true; fi
if [[ ${goals} =~ ^.*fixtags.* ]]; then fixMavenTags=true; fi
if [[ ${goals} =~ ^.*deploy.* ]]; then deploy=true; fi
fi

if [[ $key =~ ^-start-commit=.* ]]
then
startCommit=${key##*=}
fi

done

git checkout -f $headBranchShortName
#git reset --hard origin/$headBranchShortName


prepareCmd="mvn -B -P$profile release:prepare -DtagNameFormat=@{project.version}-release"
if [ ignoreSnapshots ]; then prepareCmd="$prepareCmd -DignoreSnapshots"; fi
if [ skipTests ]; then prepareCmd="$prepareCmd -Darguments='-Dmaven.test.skip=true'"; fi
if [ -z $username ]; then :; else prepareCmd="$prepareCmd -Dusername=$username"; fi
if [ -z $password ]; then :; else prepareCmd="$prepareCmd -Dpassword=$password"; fi

deployCmd="mvn clean package deploy:deploy -P$profile "
if [ skipTests ]; then deployCmd="$deployCmd -Dmaven.test.skip=true"; fi

#echo $prepareCmd
#echo $deployCmd

#exit 1;

if [[ $(mvn dependency:resolve | grep 'BUILD FAILURE') ]]
then
echo "FAILURE - Not all dependencies were resolved. Please call mvn dependency:resolve to check what's missing.";
exit 1;
fi

currentVersion=$(cat ./pom.xml | grep -m 1 '<version>' | sed -e 's/\( *\)<version>\(.*\)<\/version>/\2/')
echo "Current Version: $currentVersion"

if [[ ! $currentVersion =~ ^.*-SNAPSHOT ]]
then
echo "Expected a -SNAPSHOT version of project to start release procedure";
exit 1;
fi

#headBranchShortName=$(git symbolic-ref --short -q HEAD)
echo "Starting in branch $headBranchShortName"

versionBase=${currentVersion%-*}
minorVersion=${versionBase##*.}
versionPrefix=${versionBase%%.*}
echo "Version base: $versionBase"
echo "Version prefix: $versionPrefix"
let "minorVersion += 1"
echo "New minor version: $minorVersion"
newVersion="$versionPrefix.$minorVersion"
newDevelopmentVersion="$newVersion-SNAPSHOT"
echo "New Development Version: $newDevelopmentVersion"

branchName="$versionBase.x"
branchVersion="$versionBase.0-SNAPSHOT"
echo "Branch Name: $branchName"
echo "Version in branch: $branchVersion"

echo "createBranch=$createBranch"


if [  createBranch ]
then
echo "================================================================================"
echo "Creating branch $branchName and updating versions and scm info"
echo "================================================================================"

git branch ${branchName} ${startCommit}
git checkout ${branchName}

mvn versions:set -DnewVersion=${branchVersion}

function updateTagInPomXml() {
cat ./pom.xml | sed -e "s/<tag>.*<\/tag>/<tag>$1<\/tag>/" > pom_updated_tag.xml
mv ./pom_updated_tag.xml ./pom.xml
}

updateTagInPomXml $branchName


git add ./pom.xml
git commit -m "release.sh: seting version ${branchVersion} for branch ${branchName}"

echo "Pushing $branchName"
git push origin ${branchName}

#exit 1
if [[ "$startCommit" == "HEAD" ]]
then
git checkout $headBranchShortName;

mvn versions:set -DnewVersion=${newDevelopmentVersion}
git add ./pom.xml
git commit -m "release.sh: setting version for next development iteration: $newDevelopmentVersion"
fi

echo "Pushing $headBranchShortName"
git push origin ${headBranchShortName};

fi

exit 1

echo "prepareRelease=$prepareRelease"
if [ prepareRelease ]
then
echo "================================================================================"
echo "Preparing Release of version $versionBase from branch $branchName"
echo "================================================================================"

git checkout ${branchName}

echo "Executing:"
echo $prepareCmd
$prepareCmd
fi

echo "fixMavenTags=$fixMavenTags"
if [[ prepareRelease && fixMavenTags ]]
then

echo "================================================================================"
echo "Fixing maven release plugin bug with release tagging in scm"
echo "================================================================================"

currentVersion=$(cat ./pom.xml | grep -m 1 '<version>' | sed -e 's/\( *\)<version>\(.*\)<\/version>/\2/')
echo "Current Version before release preparation: $currentVersion"

if [[ ! $currentVersion =~ ^.*-SNAPSHOT ]]
then
echo "Expected a -SNAPSHOT version of project to start release procedure";
exit 1;
fi

releaseVersion=${currentVersion%-*}
minorVersion=${releaseVersion##*.}
versionPrefix=${releaseVersion%.*}
let "minorVersion -= 1"
releaseVersion="$versionPrefix.$minorVersion"

git tag -d "$releaseVersion-release"
mvn versions:set -DnewVersion="${releaseVersion}"
updateTagInPomXml "$releaseVersion-release"
git add ./pom.xml
git commit -m "release.sh: setting version for release: ${releaseVersion}"

git tag "$releaseVersion-release"

minorVersion=${releaseVersion##*.}
versionPrefix=${releaseVersion%.*}
#echo "Version base: $versionBase"
#echo "Version prefix: $versionPrefix"
#let "minorVersion += 1"
#echo "New minor version: $minorVersion"
#newVersion="$versionPrefix.$minorVersion"
newDevelopmentVersion=$currentVersion

mvn versions:set -DnewVersion="${newDevelopmentVersion}"
git add ./pom.xml
git commit -m "release.sh: setting next development version: ${newDevelopmentVersion}"

echo "================================================================================"
echo "FINISHED - Fixing maven release plugin bug with release tagging in scm"
echo "================================================================================"

fi

git push origin --tags
git push origin --all

if [ deploy ]
then
echo "================================================================================"
echo "Performing deploy of $releaseVersion-release to repository"
echo "================================================================================"


git checkout "$releaseVersion-release"
$deployCmd
fi

echo "================================================================================"
echo "THE END"
echo "================================================================================"
