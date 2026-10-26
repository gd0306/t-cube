import { app, dialog } from 'electron';
import { DesktopApplication, userDataDirectory } from './desktop';

app.setName('T-Cube');
app.setPath('userData', userDataDirectory(process.platform, app.getPath('appData')));
const locked = app.requestSingleInstanceLock();
if (!locked) app.quit();
else {
    app.on('window-all-closed', () => { /* The tray keeps the launcher running. */ });
    void app.whenReady().then(async () => {
        const desktop = new DesktopApplication();
        await desktop.start();
    }).catch(error => { dialog.showErrorBox('T-Cube could not start', String(error)); app.quit(); });
}
