# Godot loads the plugin with Class.forName + getConstructor(Godot). The class is only named
# in manifest meta-data, so a release minify deletes it (and the widget stays on the empty layout)
# unless these rules are applied. The widget receiver is kept as a component; the plugin is not.
-keep class com.daltongoesfast.spdtactics.patrol.PatrolWidgetPlugin {
    public <init>(org.godotengine.godot.Godot);
    public *;
}
-keep class com.daltongoesfast.spdtactics.patrol.** { *; }
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,AnnotationDefault
