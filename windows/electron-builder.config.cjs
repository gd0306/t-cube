const publisher = process.env.TCUBE_UPDATE_PUBLISHER?.trim();
module.exports = {
    extraMetadata: { tcubeUpdatePublisher: publisher || null },
    appId: 'local.tcube.launcher.windows',
    productName: 'T-Cube',
    executableName: 'T-Cube',
    directories: { output: 'release', buildResources: 'assets' },
    files: ['dist/**/*', 'package.json'],
    // Worker threads and PowerShell discovery use actual filesystem paths.
    // Keeping the small bundled app unpacked preserves those native paths.
    asar: false,
    npmRebuild: false,
    win: {
        target: [{ target: 'nsis', arch: ['x64'] }],
        ...(publisher ? { publisherName: publisher } : {}),
        verifyUpdateCodeSignature: true,
        icon: 'assets/icon.ico',
        artifactName: 'T-Cube-${version}-windows-${arch}-setup.${ext}',
    },
    nsis: {
        oneClick: false,
        perMachine: false,
        allowElevation: false,
        allowToChangeInstallationDirectory: true,
        createDesktopShortcut: true,
        createStartMenuShortcut: true,
        deleteAppDataOnUninstall: false,
        runAfterFinish: false,
        include: 'assets/installer.nsh',
    },
    publish: { provider: 'github', owner: 'gd0306', repo: 't-cube', private: false, protocol: 'https', releaseType: 'release' },
};
