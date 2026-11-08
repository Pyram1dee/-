#include <amxmodx>

#define PLUGIN "CSO Custom Core"
#define VERSION "0.1.0"
#define AUTHOR "CSO Custom Project"

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /cso", "cmd_info")
    register_clcmd("say_team /cso", "cmd_info")
    register_cvar("cso_custom_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY)
}

public cmd_info(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED

    client_print(id, print_chat, "[CSO] Custom Edition core loaded. Features under development.")
    return PLUGIN_HANDLED
}
