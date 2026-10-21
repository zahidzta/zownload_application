// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Process;
import android.provider.MediaStore;
import android.util.Log;

// Runs under the separate test APK UID, without relying on the target app's
// Kotlin runtime. The shell can trigger it but cannot lend it shell privileges.
public final class ZipVisibilityReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String rawUri = intent.getStringExtra("uri");
        if (rawUri == null) return;
        Uri uri = Uri.parse(rawUri);
        try (Cursor cursor = context.getContentResolver().query(
                uri, new String[] { MediaStore.Downloads._ID }, null, null, null)) {
            boolean visible = cursor != null && cursor.moveToFirst();
            Log.i("Zownload0C13", "ZIP_VISIBILITY uid=" + Process.myUid()
                    + " uri=" + uri + " visible=" + visible);
        } catch (Exception error) {
            Log.i("Zownload0C13", "ZIP_VISIBILITY uid=" + Process.myUid()
                    + " uri=" + uri + " visible=false error=" + error.getClass().getSimpleName());
        }
    }
}
