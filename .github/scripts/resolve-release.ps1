$ErrorActionPreference = 'Stop'

if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch') {
    $version = $env:RELEASE_VERSION
    $tag = "v$version"
} elseif ($env:GITHUB_EVENT_NAME -eq 'push' -and $env:GITHUB_REF_TYPE -eq 'tag') {
    $tag = $env:GITHUB_REF_NAME
    $version = $tag -creplace '^v', ''
} else {
    throw 'Releases require a manual run or a version tag.'
}
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw 'Use one version such as 1.0.5 (tag: v1.0.5), without leading zeroes or a prerelease suffix.'
}
$parts = $version.Split('.')
if ([decimal]$parts[0] -gt 255 -or [decimal]$parts[1] -gt 255 -or [decimal]$parts[2] -gt 65535) {
    throw 'MSI limits: major/minor <= 255; patch <= 65535.'
}
$commit = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the source commit.' }
git merge-base --is-ancestor $commit refs/remotes/origin/stable
if ($LASTEXITCODE -ne 0) { throw 'Only commits in the stable branch can be released.' }

# Windows historically used four-part release tags. MSI upgrade comparison ignores
# the fourth component, so require a new three-part version family for new releases.
$legacy = @(git tag --list "$version.*" "v$version.*" | Where-Object {
    $_ -cmatch ("^v?" + [regex]::Escape($version) + '\.[0-9]+$')
})
if ($LASTEXITCODE -ne 0) { throw 'Cannot check historical Windows version tags.' }
if ($legacy.Count -gt 0) {
    throw "Version family $version already has a four-part Windows tag ($($legacy -join ', ')). Increment the three-part patch version."
}

# The repository has historical releases with unprefixed numeric tags.
foreach ($candidate in @("v$version", $version)) {
    git rev-parse --verify --quiet "refs/tags/$candidate" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $tagCommit = git rev-parse "refs/tags/$candidate^{commit}"
        if ($LASTEXITCODE -ne 0) { throw "Cannot resolve tag $candidate." }
        if ($tagCommit -ne $commit) { throw "Tag $candidate points to different source code. Choose a new version." }
    } elseif ($LASTEXITCODE -ne 1) {
        throw 'Cannot check version tags.'
    }
}
"version=$version" >> $env:GITHUB_OUTPUT
"tag=$tag" >> $env:GITHUB_OUTPUT
"commit=$commit" >> $env:GITHUB_OUTPUT
exit 0
