<#
.SYNOPSIS
    Hace que la ventana maximizada respete la barra de tareas.

.DESCRIPTION
    Una ventana con WindowStyle="None" -es decir, con su propia barra de
    titulo dibujada, como esta- se maximiza ocupando la PANTALLA ENTERA en
    vez del area de trabajo. El resultado es que el borde inferior se mete
    por debajo de la barra de tareas y, si la barra esta arriba o a un
    lado, además tapa la propia barra de titulo del programa.

    No es un descuido de WPF: cuando Windows no dibuja el marco, tampoco
    calcula los límites. Quien tiene que hacerlo es la ventana, respondiendo
    al mensaje WM_GETMINMAXINFO, que es donde el sistema pregunta cuanto
    quiere que ocupe al maximizarse.

    Se resuelve por monitor y no con una constante, porque el area de
    trabajo cambia entre pantallas: barra de tareas oculta, en vertical, en
    un lado, o un segundo monitor que no la tiene.

    Todo esto vive aparte de Window.ps1 porque es interoperabilidad con
    Win32 y no tiene nada que ver con la lógica de la ventana; y aparte de
    Xaml.ps1 porque aquello es texto puro y esto solo funciona en Windows.
#>

function Initialize-InteropVentana {
    <#
    .SYNOPSIS
        Compila una sola vez los tipos de Win32 que hacen falta.
    #>
    [CmdletBinding()]
    param()

    if ('Cachivache.Interop' -as [type]) { return }

    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Cachivache
{
    [StructLayout(LayoutKind.Sequential)]
    public struct PUNTO { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECTANGULO { public int Izq; public int Arriba; public int Der; public int Abajo; }

    /// <summary>Lo que Windows pide en WM_GETMINMAXINFO. El orden y el
    /// tamaño de los campos son los de la estructura MINMAXINFO de la
    /// API: no se pueden reordenar.</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct MINMAXINFO
    {
        public PUNTO Reservado;
        public PUNTO MaxSize;
        public PUNTO PosicionMaxima;
        public PUNTO SeguimientoMinimo;
        public PUNTO SeguimientoMaximo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INFOMONITOR
    {
        public int Size;
        public RECTANGULO Monitor;      // toda la pantalla
        public RECTANGULO AreaTrabajo;  // lo que queda libre sin la barra de tareas
        public uint Banderas;
    }

    public static class Interop
    {
        public const int WM_GETMINMAXINFO = 0x0024;
        private const int MONITOR_MAS_CERCANO = 0x00000002;

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr ventana, int banderas);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref INFOMONITOR info);

        /// <summary>Reescribe la MINMAXINFO que apunta lParam para que la
        /// ventana se maximice sobre el AREA DE TRABAJO del monitor donde
        /// esta, no sobre la pantalla completa.</summary>
        public static void AjustarAlAreaDeTrabajo(IntPtr ventana, IntPtr lParam)
        {
            IntPtr monitor = MonitorFromWindow(ventana, MONITOR_MAS_CERCANO);
            if (monitor == IntPtr.Zero) { return; }

            INFOMONITOR info = new INFOMONITOR();
            info.Size = Marshal.SizeOf(typeof(INFOMONITOR));
            if (!GetMonitorInfo(monitor, ref info)) { return; }

            MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(lParam, typeof(MINMAXINFO));

            // Las coordenadas van RELATIVAS al monitor, no a la pantalla
            // virtual: en un segundo monitor a la izquierda del principal,
            // usar las absolutas coloca la ventana fuera de sitio.
            mmi.PosicionMaxima.X = info.AreaTrabajo.Izq   - info.Monitor.Izq;
            mmi.PosicionMaxima.Y = info.AreaTrabajo.Arriba - info.Monitor.Arriba;
            mmi.MaxSize.X  = info.AreaTrabajo.Der   - info.AreaTrabajo.Izq;
            mmi.MaxSize.Y  = info.AreaTrabajo.Abajo - info.AreaTrabajo.Arriba;

            Marshal.StructureToPtr(mmi, lParam, true);
        }
    }
}
'@
}

function Register-LimiteMaximizado {
    <#
    .SYNOPSIS
        Engancha el ajuste a una ventana ya creada.

    .DESCRIPTION
        Tiene que hacerse cuando la ventana YA tiene identificador, es
        decir, en SourceInitialized: antes de ese momento no hay un HWND al
        que engancharse. Si algo de esto falla -otra versión de Windows,
        permisos raros-, se registra y se sigue: una ventana que se maximiza
        de más es un defecto, no un motivo para no abrir.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Ventana)

    $Ventana.Add_SourceInitialized({
        try {
            Initialize-InteropVentana
            $fuente = [Windows.Interop.HwndSource]::FromHwnd(
                (New-Object Windows.Interop.WindowInteropHelper($Ventana)).Handle)
            if ($null -eq $fuente) { return }

            $fuente.AddHook([Windows.Interop.HwndSourceHook] {
                param($hwnd, $mensaje, $wParam, $lParam, $manejado)
                if ($mensaje -eq [Cachivache.Interop]::WM_GETMINMAXINFO) {
                    [Cachivache.Interop]::AjustarAlAreaDeTrabajo($hwnd, $lParam)
                }
                # NO se marca como manejado: solo se corrigen los límites y
                # se deja que Windows siga con su trabajo.
                return [IntPtr]::Zero
            })
        } catch {
            Write-Registro -Nivel 'AVISO' -Mensaje (
                'No se ha podido ajustar el maximizado a la barra de tareas: {0}' -f $_.Exception.Message)
        }
    }.GetNewClosure())
}
