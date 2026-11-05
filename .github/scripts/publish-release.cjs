const fs = require('node:fs');
const path = require('node:path');

module.exports = async ({ github, context, core }) => {
  const version = process.env.RELEASE_VERSION;
  const tag = process.env.RELEASE_TAG;
  const commit = process.env.RELEASE_COMMIT;
  const libraries = process.env.LIBRARIES_COMMIT;
  // Match the actual checked-out stable commit, not the dispatching branch's SHA.
  for (const candidate of [version, `v${version}`]) {
    try {
      await github.rest.repos.getReleaseByTag({ ...context.repo, tag: candidate });
      throw new Error(`Release ${candidate} already exists. Existing assets will not be overwritten.`);
    } catch (error) {
      if (error.status !== 404) throw error;
    }
  }
  // Protect historical four-part Windows tags, including tags created during this build.
  const legacyPattern = new RegExp('^refs/tags/v?' + version.replaceAll('.', '[.]') + '[.][0-9]+$');
  for (const prefix of [version, `v${version}`]) {
    const refs = await github.paginate(github.rest.git.listMatchingRefs, {
      ...context.repo, ref: `tags/${prefix}.`, per_page: 100
    });
    if (refs.some(ref => legacyPattern.test(ref.ref))) {
      throw new Error(`Version family ${version} already has a four-part Windows tag. Increment the patch version.`);
    }
  }
  const names = [`LotComPrinter_${version}.msi`, `LotComPrinter_${version}_win-x64.zip`, 'SHA256SUMS.txt'];
  for (const name of names) {
    if (!fs.statSync(path.join('packages', name)).size) throw new Error(`Empty asset: ${name}`);
  }
  // Ensure the source remains in stable and tags have not moved during the build.
  const { data: comparison } = await github.rest.repos.compareCommits({
    ...context.repo, base: commit, head: 'stable'
  });
  if (!['ahead', 'identical'].includes(comparison.status)) {
    throw new Error('The built commit is no longer in stable. Start a new run.');
  }
  let releaseTagExists = false;
  for (const candidate of [version, `v${version}`]) {
    let object;
    try {
      const { data: ref } = await github.rest.git.getRef({ ...context.repo, ref: `tags/${candidate}` });
      object = ref.object;
    } catch (error) {
      if (error.status !== 404) throw error;
    }
    if (!object) continue;
    while (object.type === 'tag') {
      const { data: annotated } = await github.rest.git.getTag({ ...context.repo, tag_sha: object.sha });
      object = annotated.object;
    }
    if (object.type !== 'commit' || object.sha !== commit) {
      throw new Error(`Tag ${candidate} points to different source code. Choose a new version.`);
    }
    if (candidate === tag) releaseTagExists = true;
  }
  if (!releaseTagExists) {
    await github.rest.git.createRef({ ...context.repo, ref: `refs/tags/${tag}`, sha: commit });
  }
  const { data: release } = await github.rest.repos.createRelease({
    ...context.repo,
    tag_name: tag,
    target_commitish: commit,
    name: `LotCom Watcher ${tag}`,
    draft: true,
    generate_release_notes: true,
    body: `Windows x64 release built from stable commit ${commit}.\n\n` +
      `LotCom-libraries revision: ${libraries}.\n\n` +
      'MSI installer and ZIP application payload include the .NET and Windows App SDK runtimes. ' +
      'SHA256SUMS.txt contains package checksums.'
  });
  for (const name of names) {
    await github.rest.repos.uploadReleaseAsset({
      ...context.repo, release_id: release.id, name,
      data: fs.readFileSync(path.join('packages', name)),
      headers: { 'content-type': 'application/octet-stream' }
    });
  }
  await core.summary.addHeading('Stable release packages ready')
    .addLink(`Review draft ${tag}`, release.html_url)
    .addRaw(`\n\nSource: ${commit}\n\nLotCom-libraries: ${libraries}\n`).write();
};
