# GitHub Workflows - Quick Reference

Automated CI/CD pipelines for building, testing, and publishing Whisper API MSI installer.

## Quick Start

### For Contributors

1. **Make your changes**
   ```bash
   git checkout -b feature/my-feature
   # Edit files...
   git add .
   git commit -m "feat: describe your changes"
   git push origin feature/my-feature
   ```

2. **Create a Pull Request**
   - GitHub automatically runs validation
   - Check the PR status (green ✓ = pass)
   - Fix any issues if validation fails

3. **Get your MSI**
   - Once PR is merged, go to Actions tab
   - Find the latest "Build and Publish MSI Installer" run
   - Download the MSI from Artifacts

### For Maintainers

1. **Create a Release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **Workflow does the rest**
   - Automatically builds MSI with version 1.0.0.0
   - Creates GitHub Release
   - Uploads MSI for users to download
   - Generates release notes with changelog

## Workflow Files

| Workflow | Triggers | Purpose |
|----------|----------|---------|
| `build-msi.yml` | Push/PR to main | Validate & build MSI artifact |
| `publish-release.yml` | Tag push (v*) | Create GitHub Release |
| `validate-pr.yml` | PR to main | Validate scripts & config |

See `.github/workflows/README.md` for detailed documentation.

## Getting MSI Files

### From Latest Build (Dev/Testing)
```
GitHub.com → Actions tab
→ "Build and Publish MSI Installer"
→ Latest successful run
→ Download from "Artifacts"
```

### From Official Release (Users)
```
GitHub.com → Releases page
→ Latest release
→ Download "Whisper-API-X.Y.Z.W.msi"
```

## Workflow Status

View all workflows:
```
https://github.com/dnias/whisper-api/actions
```

View specific workflow:
```
https://github.com/dnias/whisper-api/actions/workflows/build-msi.yml
```

## Common Tasks

### Check if Build Passed
1. Open Actions tab
2. Look for green ✓ check mark
3. Latest run at top

### Download Latest MSI
1. Go to Actions > Build and Publish MSI Installer
2. Click latest successful run
3. Scroll to "Artifacts"
4. Download "Whisper-API-X.Y.Z.W-MSI"

### Make a Release
```bash
git tag v1.0.0  # Must start with 'v'
git push origin v1.0.0
# Wait for workflow to complete
# Release appears on GitHub Releases page
```

### Fix Failed Validation
1. Read the error in PR checks
2. Fix the issue in your code
3. Commit and push the fix
4. Validation automatically re-runs

### Monitor Build Progress
1. Go to Actions tab
2. Click the running workflow
3. Expand steps to see details
4. Watch for green/red status

## Workflow Outputs

### Build MSI Workflow
- ✓ Validates PowerShell scripts
- ✓ Checks required files
- ✓ Downloads WiX Toolset
- ✓ Builds MSI installer
- ✓ Publishes as artifact
- **Output**: `Whisper-API-1.0.0.0.msi`

### Publish Release Workflow
- ✓ Builds versioned MSI
- ✓ Creates GitHub Release
- ✓ Uploads MSI file
- ✓ Generates changelog
- **Output**: Downloadable release on GitHub

### Validate PR Workflow
- ✓ Checks PowerShell syntax
- ✓ Validates JSON files
- ✓ Checks WiX XML
- ✓ Verifies required files
- **Output**: Pass/fail status on PR

## Troubleshooting

### "Build Failed" Error

**Check the logs**:
1. Click the failed workflow run
2. Expand the red ✗ step
3. Read the error message

**Common fixes**:
- **Syntax error**: Fix PowerShell script and push
- **Missing file**: Add the file and push
- **Invalid JSON**: Fix config file syntax

### "Validation Failed" on PR

1. Read the error message
2. Fix the issue in your code
3. Push the fix
4. Validation re-runs automatically

### Workflow Timeout

Workflows timeout after 6 hours (rare). If it happens:
1. Check if WiX download is slow
2. Try again (usually temporary)
3. File an issue if persists

## Tips and Tricks

### Speed Up Development
```bash
# Use draft releases to test without tag
# Make changes → Merge to main
# Download MSI from Artifacts while working on next feature
```

### Organize Releases
```bash
# Use semantic versioning:
git tag v1.0.0      # Major release
git tag v1.0.1      # Patch release
git tag v1.1.0      # Minor release
```

### Annotated Tags (Recommended)
```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

### View Workflow Details
```bash
# Show last 10 workflow runs
gh run list --workflow=build-msi.yml --limit 10

# Watch workflow in real-time
gh run watch [RUN_ID]
```

## File Structure

```
.github/workflows/
├── README.md                   # Detailed workflow docs
├── build-msi.yml              # Main build workflow
├── publish-release.yml         # Release automation
└── validate-pr.yml            # PR validation

Root directory:
├── GITHUB-WORKFLOWS.md         # This file
├── MSI-BUILD-GUIDE.md         # Building MSI locally
├── README.md                   # Full documentation
└── QUICKSTART.md              # User quick start
```

## GitHub Permissions

Workflows require:
- ✓ Read repository contents
- ✓ Create artifacts
- ✓ Create releases
- ✓ Run workflows

Standard for most repos, no special setup needed.

## Monitoring

### Email Notifications
GitHub sends emails for:
- ✓ Workflow failures
- ✓ Action required (if PR blocks merge)
- ✓ Completed releases

### Custom Notifications
Set up in GitHub Actions settings:
1. Settings > Notifications
2. Choose your preferences
3. Save

### Slack Integration (Optional)
Can be added to notify in Slack when releases happen.

## Release Process (Detailed)

```
1. Develop on feature branch
   ↓
2. Create Pull Request
   ↓
3. Workflows validate (validate-pr.yml)
   ↓
4. Merge to main (automatic build-msi.yml)
   ↓
5. Tag release (git tag v1.0.0)
   ↓
6. Push tag (git push origin v1.0.0)
   ↓
7. Workflow builds & releases (publish-release.yml)
   ↓
8. Users download from GitHub Releases
```

## Environment Details

Workflows run on:
- **OS**: Windows Server 2022 (latest)
- **Tools**:
  - PowerShell 7
  - Git
  - WiX Toolset (auto-installed)
  - Python 3.11 (pre-installed)

## Support

For workflow issues:
1. Check `.github/workflows/README.md`
2. Review the error logs
3. Create an issue in repository
4. Tag `@dnias` for help

## Related Documentation

- **Build Locally**: See `MSI-BUILD-GUIDE.md`
- **Install**: See `QUICKSTART.md`
- **Full Docs**: See `README.md`
- **WiX Details**: See `wix/BUILD_MSI.md`
- **Development**: See `.github/workflows/README.md`

---

**Last Updated**: November 2024
