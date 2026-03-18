/*******************************************************************************
  Copyright(c) 2024 QHY. All rights reserved.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Library General Public
 License version 2 as published by the Free Software Foundation.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Library General Public License for more details.

 You should have received a copy of the GNU Library General Public License
 along with this library; see the file COPYING.LIB.  If not, write to
 the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 Boston, MA 02110-1301, USA.
*******************************************************************************/

#include "qhy_mount_base.h"
#include <connectionplugins/connectionserial.h>
#include <unistd.h>
#include <libnova/ln_types.h>

QHYMountBase::QHYMountBase() : EQMod()
{
    setTelescopeConnection(CONNECTION_SERIAL);
}

const char * QHYMountBase::getDefaultName()
{
    return "QHY Mount";
}

bool QHYMountBase::initProperties()
{
    // INDI 2.0.8 does not provide a safe properties container API
    // compatible with iterating over *getProperties() here.
    // Let EQMod handle property initialization completely.
    return EQMod::initProperties();
}

bool QHYMountBase::updateProperties()
{
    // Call parent updateProperties first
    bool result = EQMod::updateProperties();

    // If connected and mount is initialized, immediately sync system time and location
    if (result && isConnected() && mount)
    {
        try
        {
            // Immediately sync system time when mount is connected
            // This overrides any incorrect time from KStars
            mount->SyncTimeAndTimezone();  // Uses system time

            LOG_INFO("QHY Mount initial time synchronization completed with system time");
        }
        catch (EQModError &e)
        {
            LOGF_WARN("QHY Mount initial time synchronization failed: %s", e.message);
            // Don't fail the connection for time sync issues
        }

        try
        {
            // Also sync current location coordinates
            mount->SyncLocationCoordinates();  // Uses current location from EQMod

            LOG_INFO("QHY Mount initial location synchronization completed");
        }
        catch (EQModError &e)
        {
            LOGF_WARN("QHY Mount initial location synchronization failed: %s", e.message);
            // Don't fail the connection for location sync issues
        }
    }

    return result;
}

bool QHYMountBase::updateTime(ln_date *utc, double utc_offset)
{
    // Log the time that KStars is trying to set
    LOGF_INFO("KStars trying to set time: %04d-%02d-%02d %02d:%02d:%02.0f UTC, offset: %.2f hours",
              utc->years, utc->months, utc->days, utc->hours, utc->minutes, utc->seconds, utc_offset);

    // Call parent updateTime first
    bool result = EQMod::updateTime(utc, utc_offset);

    // If connected and mount is initialized, sync time and timezone to QHY mount
    // ALWAYS use system time instead of KStars time to ensure accuracy
    if (result && isConnected() && mount)
    {
        try
        {
            // Always use system time instead of KStars time for QHY mount
            // This ensures the mount gets the correct time even if KStars has time issues
            mount->SyncTimeAndTimezone();  // This uses system time

            LOG_INFO("QHY Mount time synchronization completed with system time (ignoring KStars time)");
        }
        catch (EQModError &e)
        {
            LOGF_WARN("QHY Mount time synchronization failed: %s", e.message);
            // Don't fail the time update for sync issues
        }
    }

    return result;
}

bool QHYMountBase::updateLocation(double latitude, double longitude, double elevation)
{
    // Call parent updateLocation first
    bool result = EQMod::updateLocation(latitude, longitude, elevation);

    // If connected and mount is initialized, sync location coordinates to QHY mount
    if (result && isConnected() && mount)
    {
        try
        {
            // Sync location coordinates to the mount
            mount->SyncLocationCoordinates(latitude, longitude, elevation);

            LOGF_INFO("QHY Mount location synchronization completed: Lat %.6f°, Lon %.6f°, Elev %.0fm",
                      latitude, longitude, elevation);
        }
        catch (EQModError &e)
        {
            LOGF_WARN("QHY Mount location synchronization failed: %s", e.message);
            // Don't fail the location update for sync issues
        }
    }

    return result;
}