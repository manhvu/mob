# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags configured
# in the SDK/proguard-android.txt configuration file.

# Preserve JNI native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve DalaBridge class
-keep class com.example.dala.DalaBridge { *; }

# Preserve JNI related classes
-keep class jni.** { *; }

# Keep serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
