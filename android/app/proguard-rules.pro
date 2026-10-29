# Geolocator can use Play Services, but Radar Local forces Android LocationManager.
# These optional classes are deliberately excluded for the F-Droid build.
-dontwarn com.google.android.gms.common.GoogleApiAvailability
-dontwarn com.google.android.gms.location.FusedLocationProviderClient
-dontwarn com.google.android.gms.location.LocationCallback
-dontwarn com.google.android.gms.location.LocationRequest$Builder
-dontwarn com.google.android.gms.location.LocationRequest
-dontwarn com.google.android.gms.location.LocationServices
-dontwarn com.google.android.gms.location.LocationSettingsRequest$Builder
-dontwarn com.google.android.gms.location.LocationSettingsRequest
-dontwarn com.google.android.gms.location.SettingsClient
-dontwarn com.google.android.gms.tasks.OnCompleteListener
-dontwarn com.google.android.gms.tasks.OnFailureListener
-dontwarn com.google.android.gms.tasks.OnSuccessListener
-dontwarn com.google.android.gms.tasks.Task
