<#
.SYNOPSIS
    Tipos de datos que consume la interfaz.

.DESCRIPTION
    WPF necesita objetos que implementen INotifyPropertyChanged para que la
    casilla de una fila y el resumen del pie se mantengan sincronizados. Un
    PSCustomObject no lo hace, así que se compilan estas clases al arrancar.

    Las clases no dependen de WPF: los colores y las visibilidades viajan
    como cadenas y el motor de enlace de datos las convierte al tipo real.
#>

function Initialize-TiposInterfaz {
    [CmdletBinding()]
    param()

    if ('Cachivache.ItemVista' -as [type]) { return }

    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.ComponentModel;

namespace Cachivache
{
    /// <summary>Base con notificacion de cambios para el enlace de datos.</summary>
    public abstract class Notificable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        protected void Avisar(string propiedad)
        {
            PropertyChangedEventHandler manejador = PropertyChanged;
            if (manejador != null)
            {
                manejador(this, new PropertyChangedEventArgs(propiedad));
            }
        }
    }

    /// <summary>Un modulo de limpieza tal y como se muestra en Inicio.</summary>
    public class ModuloVista : Notificable
    {
        private bool _seleccionado;

        public string Id { get; set; }
        public string Nombre { get; set; }
        public string Descripcion { get; set; }
        public string Riesgo { get; set; }
        public string ColorRiesgo { get; set; }
        public string Nota { get; set; }
        public bool Disponible { get; set; }

        public bool Seleccionado
        {
            get { return _seleccionado; }
            set
            {
                if (_seleccionado == value) { return; }
                _seleccionado = value;
                Avisar("Seleccionado");
            }
        }

        public string VisibilidadNota
        {
            get { return string.IsNullOrEmpty(Nota) ? "Collapsed" : "Visible"; }
        }
    }

    /// <summary>Un elemento encontrado, tal y como se muestra en Resultados.</summary>
    public class ItemVista : Notificable
    {
        private bool _seleccionado;
        private bool _hecho;
        private string _estado = "";

        public string Categoria { get; set; }
        public string Nombre { get; set; }
        public string Ruta { get; set; }
        public string Info { get; set; }
        public string Efecto { get; set; }
        public string Aviso { get; set; }
        public string Metodo { get; set; }
        public string Comando { get; set; }
        public string Riesgo { get; set; }
        public string ColorRiesgo { get; set; }
        public string Tamano { get; set; }
        public double Bytes { get; set; }
        public bool Borrable { get; set; }

        /// <summary>Referencia al candidato original de PowerShell.</summary>
        public object Origen { get; set; }

        public bool Seleccionado
        {
            get { return _seleccionado; }
            set
            {
                if (_seleccionado == value) { return; }
                _seleccionado = value;
                Avisar("Seleccionado");
            }
        }

        public bool Hecho
        {
            get { return _hecho; }
            set
            {
                if (_hecho == value) { return; }
                _hecho = value;
                Avisar("Hecho");
                // EstadoEsFallo depende tambien de esto. Ver [USO-02].
                Avisar("EstadoEsFallo");
            }
        }

        public string Estado
        {
            get { return _estado; }
            set
            {
                if (_estado == value) { return; }
                _estado = value;
                Avisar("Estado");
                // Las dos propiedades derivadas dependen de esta, y WPF no
                // lo adivina: sin avisar tambien de ellas, la fila se
                // quedaria con el color y la visibilidad de antes.
                Avisar("VisibilidadEstado");
                Avisar("EstadoEsFallo");
                Avisar("TextoCompleto");
            }
        }

        /// <summary>Se ve SIEMPRE que haya algo que contar, tanto si el
        /// borrado salio bien como si no.
        ///
        /// Antes estaba atada a Hecho, asi que un elemento que NO se pudo
        /// borrar no ensenyaba absolutamente nada: la fila se quedaba
        /// igual que antes de intentarlo y el usuario daba por hecho que
        /// se habia limpiado. El unico rastro estaba en el registro, que
        /// nadie abre. Ver [USO-02] en docs/HOJA-DE-RUTA.md.</summary>
        public string VisibilidadEstado
        {
            get { return string.IsNullOrEmpty(Estado) ? "Collapsed" : "Visible"; }
        }

        /// <summary>Si lo que hay que contar es un fallo. Decide el COLOR.
        ///
        /// El texto se pintaba con el verde de exito fijo, asi que un
        /// borrado que fallo -cuando llegaba a verse- salia en verde,
        /// diciendo lo contrario de lo que ponia. Es la misma familia que
        /// [SEG-20] y [COR-01]: el programa contando algo distinto de lo
        /// que hizo, solo que aqui lo dice con el color.
        ///
        /// Se deriva de Hecho y no de una bandera aparte para que no
        /// puedan contradecirse: si no esta hecho y hay algo que decir,
        /// eso que hay que decir es un problema.</summary>
        public bool EstadoEsFallo
        {
            get { return !Hecho && !string.IsNullOrEmpty(Estado); }
        }

        /// <summary>Los cuatro textos de la columna "que pasa si se borra",
        /// juntos, para la ayuda emergente.
        ///
        /// La celda apila aviso, efecto, comando y estado. Con la altura de
        /// fila fija en 52 px cabian unas dos lineas y el resto se cortaba
        /// sin puntos suspensivos: la columna sobre la que el usuario
        /// decide si borra algo era la que se recortaba en silencio. La
        /// altura ya es automatica, pero esto se queda como red.
        /// Ver [USO-01] en docs/HOJA-DE-RUTA.md.</summary>
        public string TextoCompleto
        {
            get
            {
                var partes = new System.Collections.Generic.List<string>();
                if (!string.IsNullOrWhiteSpace(Aviso))   { partes.Add("Atención: " + Aviso); }
                if (!string.IsNullOrWhiteSpace(Efecto))  { partes.Add(Efecto); }
                if (!string.IsNullOrWhiteSpace(Comando)) { partes.Add("Ejecuta: " + Comando); }
                if (!string.IsNullOrWhiteSpace(Estado))  { partes.Add(Estado); }
                if (!string.IsNullOrWhiteSpace(MotivoMarcado)) { partes.Add(MotivoMarcado); }
                return string.Join("\n\n", partes.ToArray());
            }
        }

        /// <summary>Por que el programa lo marco solo, o por que no.
        ///
        /// El criterio existia y estaba documentado en el README, en
        /// ARQUITECTURA.md y en el panel "Acerca de": tres sitios donde
        /// nadie mira mientras decide que borrar. Aqui viaja pegado al
        /// elemento, para poder ensenyarlo donde se decide.
        ///
        /// Lo rellena quien construye la fila, llamando a
        /// Get-MotivoPremarcado: la MISMA funcion de la que sale la
        /// decision. Ver [CNF-05].</summary>
        public string MotivoMarcado { get; set; }

        /// <summary>La clave con la que este elemento se compara contra la
        /// lista de "no tocar nunca" del usuario.
        ///
        /// VIENE DEL CANDIDATO TAL CUAL; aqui no se calcula nada. Quien
        /// decide su forma es Get-ClaveExclusion: la ruta cuando la hay, y
        /// una cadena sintetica con una barra vertical cuando no, porque
        /// para un comando o para la papelera la ruta es una ETIQUETA y
        /// compararla como si fuera una carpeta no significa nada.
        ///
        /// La orden "Excluir siempre esto" del menu contextual guarda
        /// EXACTAMENTE esta cadena. Reconstruirla en la ventana seria un
        /// segundo sitio calculando la misma clave, y asi es como se llega
        /// a excluir una cosa y comparar otra. Ver [USO-06] y [ARQ-03].</summary>
        public string ClaveExclusion { get; set; }

        /// <summary>Si Ruta es una ruta de verdad y no una etiqueta.
        ///
        /// "Copiar ruta" sobre un comando del sistema o sobre la papelera
        /// dejaria en el portapapeles algo que PARECE una ruta y no lo es,
        /// y quien lo pegue en el Explorador o en un guion no tiene forma
        /// de saberlo: el portapapeles no ensenya de donde salio.
        ///
        /// La pregunta se contesta con la clave de exclusion en vez de con
        /// una segunda regla propia. Get-ClaveExclusion devuelve la ruta
        /// TAL CUAL cuando la hay, asi que "la clave es la ruta" significa
        /// exactamente "la ruta es de verdad". Una sola regla, en un solo
        /// sitio, y ademas ya probada -incluido el caso que fallo en
        /// [ARQ-03], donde una regla escrita a mano solo era correcta en
        /// Windows y la suite corre en Linux. Ver [USO-06].</summary>
        public bool TieneRutaReal
        {
            get
            {
                return !string.IsNullOrWhiteSpace(Ruta) &&
                       string.Equals(Ruta, ClaveExclusion, StringComparison.Ordinal);
            }
        }

        /// <summary>El riesgo como NUMERO, para poder ordenar por el.
        ///
        /// Ordenar por la cadena "Riesgo" daria Alto, Bajo, Medio: el orden
        /// del diccionario, que no significa nada. Lo que el usuario quiere
        /// al pulsar esa cabecera es "ensename primero lo que hay que
        /// mirar", o sea Alto, Medio, Bajo.
        ///
        /// Una ordenacion que produce un orden sin sentido es peor que no
        /// poder ordenar: parece que funciona. Ver [USO-03].</summary>
        public int OrdenRiesgo
        {
            get
            {
                if (Riesgo == "Alto")  { return 0; }
                if (Riesgo == "Medio") { return 1; }
                return 2;
            }
        }

        public string VisibilidadAviso
        {
            get { return string.IsNullOrEmpty(Aviso) ? "Collapsed" : "Visible"; }
        }

        /// <summary>Solo el metodo 'Comando' declara un comando externo:
        /// SECURITY.md exige que sea "siempre visible en la interfaz".
        /// Ver [C-03] en docs/OPTIMIZACIONES.md.</summary>
        public string VisibilidadComando
        {
            get { return string.IsNullOrEmpty(Comando) ? "Collapsed" : "Visible"; }
        }
    }

    /// <summary>Una unidad de disco en el panel lateral.</summary>
    public class DiscoVista : Notificable
    {
        private bool _seleccionado = true;

        public string Letra { get; set; }
        public string Titulo { get; set; }
        public string Detalle { get; set; }
        public string Porcentaje { get; set; }
        public string ColorBarra { get; set; }
        public double AnchoUsado { get; set; }

        /// <summary>Si esta unidad entra en el analisis. Notifica cambios
        /// porque la casilla la marca el usuario en cualquier momento.</summary>
        public bool Seleccionado
        {
            get { return _seleccionado; }
            set
            {
                if (_seleccionado == value) { return; }
                _seleccionado = value;
                Avisar("Seleccionado");
            }
        }
    }

    /// <summary>Un perfil de limpieza en el selector de Inicio.</summary>
    public class PerfilVista : Notificable
    {
        private bool _activo;

        public string Id { get; set; }
        public string Nombre { get; set; }
        public string Resumen { get; set; }

        public bool Activo
        {
            get { return _activo; }
            set
            {
                if (_activo == value) { return; }
                _activo = value;
                Avisar("Activo");
            }
        }
    }

    /// <summary>Una ejecucion anterior en el historial.</summary>
    public class HistorialVista
    {
        public string Tipo { get; set; }
        public string Titulo { get; set; }
        public string Detalle { get; set; }
        public string Tamano { get; set; }
        public string ColorTipo { get; set; }

        /// <summary>Informe de esta ejecucion, ya validado contra la
        /// carpeta de informes. Cadena vacia si no hay ninguno que se
        /// pueda abrir: las entradas anteriores a esta version no lo
        /// guardaban, y un informe se puede borrar a mano en cualquier
        /// momento.</summary>
        public string Informe { get; set; }

        /// <summary>Texto del pie de la tarjeta. Se calcula aqui y no en
        /// el XAML para que la tarjeta diga la verdad en los dos casos en
        /// vez de invitar a pulsar algo que no va a hacer nada.</summary>
        public string PieInforme
        {
            get
            {
                return string.IsNullOrEmpty(Informe)
                    ? "Sin informe guardado de esta ejecución."
                    : "Pulsa para abrir el informe.";
            }
        }
    }

    /// <summary>Una exclusion del usuario, en la tarjeta de Ajustes.
    ///
    /// Los tres textos vienen HECHOS de Get-ExclusionVista, que es calculo
    /// puro y esta probado; aqui no se decide nada. La clase existe solo
    /// para que el enlace de datos de WPF tenga de donde leer.
    ///
    /// Ver [CNF-01].</summary>
    public class ExclusionVista
    {
        /// <summary>La cadena EXACTA que esta guardada en RutasExcluidas.
        ///
        /// Es la que viaja en el Tag del boton "Quitar" y la que se saca de
        /// la lista al pulsarlo. No es lo mismo que Titulo y no puede
        /// serlo: para un comando o para la papelera, Titulo es el nombre
        /// legible y la clave es "modulo:&lt;Id&gt;|&lt;Nombre&gt;". Quitar
        /// por el titulo no encontraria nada que quitar.</summary>
        public string Clave { get; set; }

        /// <summary>Lo que el usuario lee: la ruta, o el nombre del
        /// elemento cuando la clave es sintetica.</summary>
        public string Titulo { get; set; }

        /// <summary>Que clase de exclusion es y hasta donde llega.</summary>
        public string Detalle { get; set; }

        /// <summary>'carpeta', 'modulo' o 'texto'. No lo usa el XAML: viaja
        /// para poder probar que cada clave se presenta como toca.</summary>
        public string Tipo { get; set; }
    }

    /// <summary>Un informe ya generado, en la lista de Informes.</summary>
    public class InformeVista
    {
        public string Nombre { get; set; }
        public string Ruta { get; set; }
        public string Detalle { get; set; }
        public string Tamano { get; set; }
    }
}
'@
}
