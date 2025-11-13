# GitHub Actions Workflows

This directory contains automated CI/CD workflows for building, testing, and publishing the Whisper API MSI installer.

## Workflows Overview

### 1. `build-msi.yml` - Build and Publish MSI Artifact

**Trigger**:
- Push to `main` branch (any installer/script changes)
- Manual trigger via GitHub Actions UI
- Pull requests with relevant file changes

**What it does**:
1. **Validates PowerShell scripts** - Checks syntax of all `.ps1` files
2. **Verifies required files** - Ensures all files are present
3. **Downloads WiX Toolset** - Installs WiX 3.14 from GitHub releases
4. **Builds MSI** - Compiles the Windows installer
5. **Uploads artifact** - Makes MSI available for download

**Output**:
- MSI file artifact (`Whisper-API-X.Y.Z.W.msi`)
- 30-day retention
- Available in "Artifacts" section of workflow run

**Example**:
```bash
# MSI will be named: Whisper-API-1.0.0.0.msi
# Available for download in Actions > [Run] > Artifacts
```

### 2. `publish-release.yml` - Publish Release to GitHub

**Trigger**:
- Push with tag matching `v*` (e.g., `v1.0.0`)

**What it does**:
1. Validates tag format
2. Extracts version number
3. Builds MSI with that version
4. Creates GitHub Release
5. Uploads MSI as release asset
6. Generates changelog from recent commits

**Output**:
- GitHub Release page with:
  - MSI file for download
  - Installation instructions
  - Changelog
  - System requirements
  - Support links

**Example**:
```bash
# Tag: v1.0.0
# Creates: Release v1.0.0 with Whisper-API-1.0.0.0.msi
```

### 3. `validate-pr.yml` - Validate Pull Requests

**Trigger**:
- Pull requests to `main` branch
- Any changes to scripts, config, or workflows

**What it does**:
1. **Syntax validation** - Checks all PowerShell scripts
2. **JSON validation** - Validates configuration files
3. **Batch file validation** - Checks Windows batch files
4. **Required files check** - Ensures nothing is missing
5. **WiX XML validation** - Validates installer definition
6. **Content checks** - Looks for common issues
7. **Documentation validation** - Verifies documentation exists

**Output**:
- Pass/fail status on PR
- Blocks merge if validation fails

**Example**:
```
✓ All scripts valid
✓ JSON files valid
✓ Required files present
→ Ready to merge
```

## Workflow Status

All workflow results are visible in the GitHub Actions tab:
```
https://github.com/dnias/whisper-api/actions
```

## Using the Workflows

### For Developers

#### 1. Make Changes
```bash
git checkout -b feature/my-feature
# Make changes to scripts, docs, etc.
git add .
git commit -m "feat: describe your changes"
git push origin feature/my-feature
```

#### 2. Create Pull Request
- Workflows automatically validate your changes
- Check the PR status (green check = good)
- Review any failed checks

#### 3. Merge to Main
- Once approved and tests pass, merge the PR
- `build-msi.yml` workflow runs automatically
- MSI artifact is created and available

#### 4. Create Release (for maintainers)
```bash
# Tag the commit that should be released
git tag v1.0.0
git push origin v1.0.0
```

The `publish-release.yml` workflow will:
- Build the MSI
- Create a GitHub Release
- Upload MSI for download
- Generate nice release notes

### For End Users

#### Getting Latest Build
1. Go to [GitHub Actions](https://github.com/dnias/whisper-api/actions)
2. Select `Build and Publish MSI Installer` workflow
3. Click the latest successful run
4. Download MSI from "Artifacts" section

#### Getting Official Release
1. Go to [Releases](https://github.com/dnias/whisper-api/releases)
2. Download the MSI from the latest release
3. Double-click to install

## Version Management

### Version Format
```
X.Y.Z.W (e.g., 1.0.0.0)
```

### How Versions are Set

**For PR/Push builds**:
- Default version: `1.0.0.0`
- Can override via workflow input
- Not a real release

**For official releases**:
```bash
# Tag format must match: v<version>
# Examples:
git tag v1.0.0      # → 1.0.0.0
git tag v1.0.1      # → 1.0.1.0
git tag v2.0.0      # → 2.0.0.0
git tag v1.0.0-rc1  # → Invalid (must match X.Y.Z pattern)
```

## Monitoring Workflow Runs

### View Workflow Status
```
https://github.com/dnias/whisper-api/actions
```

### View Specific Workflow
```
https://github.com/dnias/whisper-api/actions/workflows/build-msi.yml
```

### View Artifacts
1. Go to workflow run
2. Scroll down to "Artifacts"
3. Download MSI file

### View Release
```
https://github.com/dnias/whisper-api/releases
```

## Troubleshooting Workflows

### Build Failed

**Check logs**:
1. Go to Actions tab
2. Click failed workflow run
3. Expand the failed step
4. Read error message

**Common issues**:

**"WiX Toolset not found"**
- Workflow tries to download from GitHub
- Check internet connectivity in Actions logs
- May need to update WiX download URL

**"MSI file not found"**
- Build step didn't complete successfully
- Check WiX compilation errors in logs
- Ensure all source files exist in repo

**"Validation failed"**
- PowerShell syntax error in scripts
- Missing required file
- Invalid JSON in config
- Fix the error and push again

### PR Validation Fails

**Syntax errors**:
1. Check the error message in PR checks
2. Fix the syntax error in your script
3. Push the fix
4. Validation re-runs automatically

**Missing files**:
1. Add the missing file
2. Commit and push
3. Validation re-runs

### Release Creation Fails

**Invalid tag**:
- Tag must match format: `v1.0.0` or `v1.0.0.0`
- Delete and recreate tag: `git tag -d v1.0.0 && git tag v1.0.0 && git push --tags`

**Build failed**:
- Check `build-msi.yml` logs
- Same troubleshooting as above

## Workflow Permissions

The workflows require:
- **Read**: Access to repository files
- **Write**: Create artifacts and releases
- **Actions**: Execute workflows

These are configured in the repo settings.

## Environment Variables

Key variables in workflows:

```yaml
MSI_VERSION: '1.0.0.0'        # Default MSI version
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}  # GitHub API access
```

## GitHub Release Notes

When a release is created, it includes:
- **Downloads** - MSI file info (size, hash)
- **Installation** - Step-by-step guide
- **Features** - What's included
- **Requirements** - System prerequisites
- **Documentation** - Links to guides
- **Recent Changes** - Commits since last release

## Best Practices

### For Maintainers
1. ✅ Always validate PRs pass checks before merging
2. ✅ Use semantic versioning for tags (v1.0.0)
3. ✅ Create releases for every version bump
4. ✅ Review generated release notes
5. ✅ Test released MSI before announcing

### For Contributors
1. ✅ Make sure PR validation passes
2. ✅ Keep commits focused (one feature per PR)
3. ✅ Provide clear commit messages
4. ✅ Test locally before pushing

### For Builds
1. ✅ Keep WiX files up to date
2. ✅ Validate locally before pushing
3. ✅ Don't modify workflows without testing
4. ✅ Monitor workflow execution times

## Workflow Details

### `build-msi.yml` Jobs

1. **validate-scripts**
   - Parses PowerShell AST
   - Checks for empty files
   - Validates file existence

2. **build-msi**
   - Downloads WiX Toolset
   - Compiles WiX source
   - Links to MSI
   - Uploads artifact
   - Generates release notes

3. **create-release** (tag-only)
   - Creates GitHub Release
   - Uploads MSI
   - Posts release notes

4. **build-summary**
   - Reports overall status
   - Summarizes results

### `publish-release.yml` Jobs

1. **publish**
   - Validates tag format
   - Builds MSI
   - Gets file info (size, hash)
   - Generates changelog
   - Creates release

### `validate-pr.yml` Jobs

1. **syntax-validation**
   - Validates PowerShell scripts
   - Validates JSON files
   - Validates batch files
   - Checks required files
   - Validates WiX XML

2. **file-content-check**
   - Checks for common issues
   - Validates documentation

3. **pr-checks-summary**
   - Reports overall status

## Performance

### Build Times
- **Validation**: ~30 seconds
- **WiX download**: ~1-2 minutes
- **MSI build**: ~30 seconds
- **Total**: ~3 minutes

### Artifact Retention
- **Default**: 30 days
- **Release assets**: Unlimited
- **Configurable**: Edit workflow file

## Security

### Secrets
No secrets are currently required. Workflows use:
- `GITHUB_TOKEN` - Automatically provided
- No credentials stored in workflows

### Best Practices
- ✅ Workflows run in isolated environments
- ✅ No secrets in output logs
- ✅ Code signing available for enterprises
- ✅ All builds are reproducible

## Customization

### Change MSI Version
Edit workflow and set version:
```yaml
env:
  MSIX_VERSION: '1.0.0.0'
```

### Change WiX Version
Update download URL:
```powershell
$wixUrl = "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314.exe"
```

### Change Retention
Edit artifact upload:
```yaml
retention-days: 30  # Change this value
```

### Add New Validation
Edit `validate-pr.yml` to add checks.

## Support and Questions

For issues with workflows:
1. Check the logs in Actions tab
2. Review this documentation
3. Check WiX Toolset documentation
4. Create an issue in the repository

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [WiX Toolset](https://wixtoolset.org/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Repository README](../README.md)
- [MSI Build Guide](../MSI-BUILD-GUIDE.md)

---

**Last Updated**: November 2024
