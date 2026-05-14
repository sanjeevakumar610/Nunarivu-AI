# ── LiteRT-LM ────────────────────────────────────────────────────────────────
# The native liblitertlm_jni.so calls GetMethodID() with these EXACT method
# names at runtime. R8 must NOT rename or remove them, otherwise the JNI
# lookup fails with NoSuchMethodError and the process SIGABRTs.
#
# Crash signature (without these rules):
#   NoSuchMethodError: no non-static method "LR2/c;.onMessage(Ljava/lang/String;)V"
#   at LiteRtLmJni.nativeSendMessageAsync(...)
#
-keep class com.google.ai.edge.litertlm.** { *; }
