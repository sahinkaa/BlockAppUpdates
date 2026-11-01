# GitHub Release Guide

## Create the repository

1. Sign in to GitHub and open <https://github.com/new>.
2. Choose your GitHub account under **Owner**.
3. Enter `Block-App-Updates` as the repository name.
4. Use this description: `Selectively block updates for individual App Store apps on rootless iOS 15 and later.`
5. Select **Public**.
6. Leave **Add a README file**, **Add .gitignore**, and **Choose a license** unselected. The release kit already contains the repository files.
7. Click **Create repository**.

## Upload the source

1. Extract `BlockAppUpdates_1.0.0_GitHub_Release_Kit.zip` on your computer.
2. Open the extracted `repository` folder.
3. On the empty GitHub repository page, click **uploading an existing file**. If that link is not shown, select **Add file → Upload files**.
4. Drag every file and folder from `repository` into the upload area.
5. Enter `Initial release` as the commit message.
6. Select **Commit directly to the main branch**.
7. Click **Commit changes**.

## Publish version 1.0.0

1. Open the repository's main page and click **Releases**.
2. Click **Draft a new release**.
3. Open **Choose a tag**, type `v1.0.0`, and choose **Create new tag: v1.0.0 on publish**.
4. Set the release title to `Block App Updates 1.0.0`.
5. Copy the contents of `release-assets/RELEASE_NOTES.md` into the description box.
6. Drag `release-assets/com.sahinkaa.blockappupdates_1.0.0_iphoneos-arm64.deb` into the release assets box.
7. Leave **Set as a pre-release** unchecked and enable **Set as the latest release** if GitHub shows that option.
8. Wait until the `.deb` upload finishes, then click **Publish release**.
