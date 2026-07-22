using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using HarmonyLib;
using UnityEngine;

namespace KerbalRuUiTranslator
{
    // Loads GameData/*/KerbalRuUiTranslations/*.txt (tab-separated "English<TAB>Russian" pairs)
    // and Harmony-patches the common legacy-IMGUI and UnityEngine.UI text entry points to
    // substitute a Russian string whenever the exact English string is known. Unknown strings
    // pass through unchanged - this can never corrupt text it doesn't recognize.
    [KSPAddon(KSPAddon.Startup.Instantly, true)]
    public class Loader : MonoBehaviour
    {
        public static readonly Dictionary<string, string> Dict = new Dictionary<string, string>(StringComparer.Ordinal);
        private static bool _patched;

        private void Awake()
        {
            // Dictionary loading and Harmony patching are independent failure domains on purpose:
            // a single unreadable/locked .txt (filesystem race, AV lock, restrictive permissions
            // on a container/Deck setup) must never prevent PatchAll from running - an empty or
            // partial Dict is harmless (unmatched strings just pass through unchanged), but a
            // skipped PatchAll silently disables translation for every mod, for the whole session
            // (KSPAddon.Instantly + Startup.Instantly means Awake runs exactly once, no retry).
            try
            {
                LoadDictionaries();
            }
            catch (Exception e)
            {
                Debug.LogError("[KerbalRuUiTranslator] dictionary load failed: " + e);
            }

            try
            {
                if (!_patched)
                {
                    var harmony = new Harmony("ru.kerbal.uitranslator");
                    harmony.PatchAll(Assembly.GetExecutingAssembly());
                    _patched = true;
                    Debug.Log("[KerbalRuUiTranslator] patched, " + Dict.Count + " strings loaded");
                }
            }
            catch (Exception e)
            {
                Debug.LogError("[KerbalRuUiTranslator] patch failed: " + e);
            }
        }

        private static void LoadDictionaries()
        {
            Dict.Clear();
            string gameData = KSPUtil.ApplicationRootPath + "GameData";
            if (!Directory.Exists(gameData)) return;

            foreach (string dir in Directory.GetDirectories(gameData, "KerbalRuUiTranslations", SearchOption.AllDirectories))
            {
                foreach (string file in Directory.GetFiles(dir, "*.txt", SearchOption.TopDirectoryOnly))
                {
                    // Isolated per file: one corrupt/locked dictionary must not lose the rest.
                    try
                    {
                        LoadFile(file);
                    }
                    catch (Exception e)
                    {
                        Debug.LogError("[KerbalRuUiTranslator] " + file + ": load failed: " + e);
                    }
                }
            }
        }

        private static void LoadFile(string path)
        {
            int loaded = 0;
            foreach (string rawLine in File.ReadAllLines(path))
            {
                string line = rawLine.Replace("\r", "");
                if (line.Length == 0 || line[0] == '#') continue;
                int tab = line.IndexOf('\t');
                if (tab < 0) continue;
                string en = line.Substring(0, tab);
                string ru = line.Substring(tab + 1);
                if (en.Length == 0) continue;
                Dict[en] = ru;
                loaded++;
            }
            Debug.Log("[KerbalRuUiTranslator] " + path + ": " + loaded + " entries");
        }

        public static string Translate(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            string ru;
            return Dict.TryGetValue(s, out ru) ? ru : s;
        }
    }

    // ---------------- Legacy IMGUI (UnityEngine.GUI / GUILayout) ----------------

    [HarmonyPatch(typeof(GUIContent))]
    [HarmonyPatch(MethodType.Constructor, new[] { typeof(string) })]
    class Patch_GUIContent_ctor1
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUIContent))]
    [HarmonyPatch(MethodType.Constructor, new[] { typeof(string), typeof(string) })]
    class Patch_GUIContent_ctor2
    {
        static void Prefix(ref string text, ref string tooltip)
        {
            text = Loader.Translate(text);
            tooltip = Loader.Translate(tooltip);
        }
    }

    [HarmonyPatch(typeof(GUIContent))]
    [HarmonyPatch(MethodType.Constructor, new[] { typeof(string), typeof(Texture) })]
    class Patch_GUIContent_ctor3
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUIContent))]
    [HarmonyPatch(MethodType.Constructor, new[] { typeof(string), typeof(Texture), typeof(string) })]
    class Patch_GUIContent_ctor4
    {
        static void Prefix(ref string text, ref string tooltip)
        {
            text = Loader.Translate(text);
            tooltip = Loader.Translate(tooltip);
        }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Label), new[] { typeof(Rect), typeof(string) })]
    class Patch_GUI_Label_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Label), new[] { typeof(Rect), typeof(string), typeof(GUIStyle) })]
    class Patch_GUI_Label_s_style
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Button), new[] { typeof(Rect), typeof(string) })]
    class Patch_GUI_Button_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Button), new[] { typeof(Rect), typeof(string), typeof(GUIStyle) })]
    class Patch_GUI_Button_s_style
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Box), new[] { typeof(Rect), typeof(string) })]
    class Patch_GUI_Box_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Toggle), new[] { typeof(Rect), typeof(bool), typeof(string) })]
    class Patch_GUI_Toggle_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Label), new[] { typeof(string), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Label_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Label), new[] { typeof(string), typeof(GUIStyle), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Label_s_style
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Button), new[] { typeof(string), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Button_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Button), new[] { typeof(string), typeof(GUIStyle), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Button_s_style
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Box), new[] { typeof(string), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Box_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Toggle), new[] { typeof(bool), typeof(string), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Toggle_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    // Window titles - the single most important entry point (every mod window has one).
    [HarmonyPatch(typeof(GUI), nameof(GUI.Window), new[] { typeof(int), typeof(Rect), typeof(GUI.WindowFunction), typeof(string) })]
    class Patch_GUI_Window_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUI), nameof(GUI.Window), new[] { typeof(int), typeof(Rect), typeof(GUI.WindowFunction), typeof(string), typeof(GUIStyle) })]
    class Patch_GUI_Window_s_style
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Window), new[] { typeof(int), typeof(Rect), typeof(GUI.WindowFunction), typeof(string), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Window_s
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    [HarmonyPatch(typeof(GUILayout), nameof(GUILayout.Window), new[] { typeof(int), typeof(Rect), typeof(GUI.WindowFunction), typeof(string), typeof(GUIStyle), typeof(GUILayoutOption[]) })]
    class Patch_GUILayout_Window_s_style
    {
        static void Prefix(ref string text) { text = Loader.Translate(text); }
    }

    // Mouse-over tooltip set directly via the static GUI.tooltip property (instead of GUIContent.tooltip).
    [HarmonyPatch(typeof(GUI), "tooltip", MethodType.Setter)]
    class Patch_GUI_set_tooltip
    {
        static void Prefix(ref string value) { value = Loader.Translate(value); }
    }

    // ---------------- UnityEngine.UI (Canvas-based text, e.g. KSP.UI.Screens settings pages) ----------------

    [HarmonyPatch(typeof(UnityEngine.UI.Text), "text", MethodType.Setter)]
    class Patch_UGUI_Text_set_text
    {
        static void Prefix(ref string value) { value = Loader.Translate(value); }
    }

    // Dropdown option labels (e.g. tank/config selectors built with UnityEngine.UI.Dropdown).
    [HarmonyPatch(typeof(UnityEngine.UI.Dropdown.OptionData), "text", MethodType.Setter)]
    class Patch_UGUI_DropdownOption_set_text
    {
        static void Prefix(ref string value) { value = Loader.Translate(value); }
    }
}
