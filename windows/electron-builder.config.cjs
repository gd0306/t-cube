module.exports = {
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
    publish: null,
};
