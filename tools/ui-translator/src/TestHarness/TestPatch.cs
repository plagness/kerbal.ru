using System;
using System.Reflection;
using HarmonyLib;

class TestPatch
{
    static int Main()
    {
        try
        {
            var asm = Assembly.LoadFrom("/Users/plag/Development/kerbal.ru/GameData/kerbalru-ui-translator/Plugins/KerbalRuUiTranslator.dll");
            var harmony = new Harmony("ru.kerbal.uitranslator.test");
            harmony.PatchAll(asm);
            var patched = harmony.GetPatchedMethods();
            int count = 0;
            foreach (var m in patched)
            {
                count++;
                Console.WriteLine("OK patched: " + m.DeclaringType + "::" + m.Name);
            }
            Console.WriteLine("TOTAL PATCHED METHODS: " + count);
            return 0;
        }
        catch (Exception e)
        {
            Console.WriteLine("FAILURE: " + e);
            return 1;
        }
    }
}
