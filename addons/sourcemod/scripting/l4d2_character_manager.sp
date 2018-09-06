//ABM https://forums.alliedmods.net/showthread.php?p=2477820
//don't use with abm's cvar enabled (abm_identityfix 1)

//Identity fix https://forums.alliedmods.net/showthread.php?t=280539
//Don't use identity fix with this plugin



#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>


#define REQUIRE_EXTENSIONS
#include <dhooks>
#undef REQUIRE_EXTENSIONS

#pragma newdecls required

#define PLUGIN_VERSION 	"1.3.1"
#define GAMEDATA		"l4d2_character_manager"


#define L4D1_SETINDEX_BILL_1			0, 4
#define L4D1_SETINDEX_ZOEY_1 			1, 5
#define L4D1_SETINDEX_LOUIS_1 			2, 7
#define L4D1_SETINDEX_FRANCIS_1			3, 6
#define L4D1_SETINDEX_BILL_2			4, 4
#define L4D1_SETINDEX_ZOEY_2			5, 5
#define L4D1_SETINDEX_FRANCIS_2			6, 6
#define L4D1_SETINDEX_LOUIS_2			7, 7

#define L4D2_SETINDEX_NICK				0, 0
#define L4D2_SETINDEX_ROCHELLE			1, 1
#define L4D2_SETINDEX_COACH				2, 2
#define L4D2_SETINDEX_ELLIS				3, 3
#define L4D2_SETINDEX_BILL				4, 4
#define L4D2_SETINDEX_ZOEY				5, 5
#define L4D2_SETINDEX_FRANCIS			6, 6
#define L4D2_SETINDEX_LOUIS				7, 7

enum L4D2_SurvivorSet
{
	L4D2_SurvivorSet_Default = 0,
	L4D2_SurvivorSet_L4D1,
	L4D2_SurvivorSet_L4D2,
	L4D2_SurvivorSet_Both
}


//credit for some of meurdo identity fix code
static char sSurvivorNames[9][] = { "Nick", "Rochelle", "Coach", "Ellis", "Bill", "Zoey", "Francis", "Louis", "AdaWong"};
static char sSurvivorModels[9][] =
{
	"models/survivors/survivor_gambler.mdl",
	"models/survivors/survivor_producer.mdl",
	"models/survivors/survivor_coach.mdl",
	"models/survivors/survivor_mechanic.mdl",
	"models/survivors/survivor_namvet.mdl",
	"models/survivors/survivor_teenangst.mdl",
	"models/survivors/survivor_biker.mdl",
	"models/survivors/survivor_manager.mdl",
	"models/survivors/survivor_adawong.mdl"
};


static char sModelTracking[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static bool bShouldIgnoreOnce[MAXPLAYERS+1];

static Handle hCvar_SurvivorSet = null;
L4D2_SurvivorSet iSurvivorSet = L4D2_SurvivorSet_Both;
L4D2_SurvivorSet iCurrentSet = L4D2_SurvivorSet_Default;


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(GetEngineVersion() != Engine_Left4Dead2 )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "[L4D2]Character_manager",
	author = "Lux, $atanic $pirit",
	description = "Sets bots to least used survivor character when spawned from(0-7)",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2607394"
};

public void OnPluginStart()
{
	CreateConVar("l4d2_character_manager_version", PLUGIN_VERSION, "l4d2_character_manager_version", FCVAR_DONTRECORD|FCVAR_NOTIFY);
	hCvar_SurvivorSet = CreateConVar("l4d2_survivor_set", "3", "survivor set you wish to use, 0 = (use map default), 1 = (l4d1), 2 = (l4d2), 3 = (use both)", FCVAR_NOTIFY, true, 0.0, true, 3.0);
	HookConVarChange(hCvar_SurvivorSet, eConvarChanged);
	AutoExecConfig(true, "l4d2_character_manager");
	
	HookEvent("bot_player_replace", eBotToPlayer, EventHookMode_Post);
	HookEvent("player_bot_replace", ePlayerToBot, EventHookMode_Post);
	HookEvent("round_start", eRoundStart, EventHookMode_Pre);
	
	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if( hGameData == null ) 
		SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);
	
	// ====================================================================================================
	// Detour	-	CTerrorGameRules::GetSurvivorSet
	// ====================================================================================================
		
	// Create a hook from config.
	Handle hDetour_OnGetSurvivorSet = DHookCreateFromConf(hGameData, "CTerrorGameRules::GetSurvivorSet");
	if( !hDetour_OnGetSurvivorSet )
		SetFailState("Failed to setup detour for CTerrorGameRules::GetSurvivorSet");
	delete hGameData;
	
	// Add a pre hook on the function.
	if (!DHookEnableDetour(hDetour_OnGetSurvivorSet, true, Detour_OnGetSurvivorSet))
		SetFailState("Failed to detour OnGetSurvivorSet.");
}

public void eConvarChanged(Handle hCvar, const char[] sOldVal, const char[] sNewVal)
{
	iSurvivorSet = view_as<L4D2_SurvivorSet>(GetConVarInt(hCvar_SurvivorSet));
	if(iCurrentSet != L4D2_SurvivorSet_L4D2)
		PrintToServer("[Character_manager]L4D2 survivor voices won't be loaded until next map.");
}

public void eRoundStart(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	for(int i = 0; i <= MaxClients; i++)
	{
		bShouldIgnoreOnce[i] = false;
		sModelTracking[i][0] = '\0';
	}
}

public void eBotToPlayer(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "player"));
	if(iClient < 1 || !IsClientInGame(iClient) || GetClientTeam(iClient) != 2 || IsFakeClient(iClient)) 
		return;
	
	int iBot = GetClientOfUserId(GetEventInt(hEvent, "bot"));
	if(iBot < 1 || !IsClientInGame(iBot) || GetClientTeam(iClient) != 2)
		return;
	
	SetEntProp(iClient, Prop_Send, "m_survivorCharacter", GetEntProp(iBot, Prop_Send, "m_survivorCharacter", 2), 2);
	char sModel[PLATFORM_MAX_PATH];
	GetEntPropString(iBot, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
	SetEntityModel(iClient, sModel);
	bShouldIgnoreOnce[iBot] = false;
}

public void ePlayerToBot(Handle hEvent, const char[] sName, bool bDontBroadcast)// CreateFakeClient this is called after SpawnPost hook
{
	int iBot = GetClientOfUserId(GetEventInt(hEvent, "bot"));
	if(iBot < 1 || !IsClientInGame(iBot) || GetClientTeam(iBot) != 2)
		return;
	
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "player"));
	if(iClient < 1 || !IsClientInGame(iClient) || GetClientTeam(iClient) != 2 || IsFakeClient(iClient) || sModelTracking[iClient][0] == '\0') // team check before fakeclient check incase of spawning infected with CreateFakeClient()
	{
		SetCharacter(iBot);
		return;
	}
	
	int iSurvivorChar = GetEntProp(iClient, Prop_Send, "m_survivorCharacter");
	SetEntProp(iBot, Prop_Send, "m_survivorCharacter", iSurvivorChar);
	SetEntityModel(iBot, sModelTracking[iClient]);
	
	if(iSurvivorChar == 2 && StrContains(sModelTracking[iClient], "survivor_adawong", false))
		SetClientInfo(iBot, "name", sSurvivorNames[8]);
	else
		for (int i = 0; i < 7; i++)
			if (StrEqual(sModelTracking[iClient], sSurvivorModels[i])) 
				SetClientInfo(iBot, "name", sSurvivorNames[i]);
	
	bShouldIgnoreOnce[iBot] = true;
}

public void OnGameFrame()
{
	static int i;
	for(i = 1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		if(GetClientTeam(i) != 2) 
		{
			sModelTracking[i][0] = '\0' ;
			continue;
		}
		
		static int iModelIndex[MAXPLAYERS+1] = {0, ...};
		if(iModelIndex[i] == GetEntProp(i, Prop_Data, "m_nModelIndex", 2))
			continue;
		
		static char sModel[PLATFORM_MAX_PATH];
		GetEntPropString(i, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
		strcopy(sModelTracking[i], PLATFORM_MAX_PATH, sModel);
	}
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if(sClassname[0] != 's' || !StrEqual(sClassname, "survivor_bot"))
	 	return;
	 
	SDKHook(iEntity, SDKHook_SpawnPost, SpawnPost);
}

public void SpawnPost(int iEntity)// before events
{
	if(!IsValidEntity(iEntity) || !IsFakeClient(iEntity))
		return;	
	
	if(GetClientTeam(iEntity) == 4)
		return;
	
	SetCharacter(iEntity);
	
	bShouldIgnoreOnce[iEntity] = false;
	RequestFrame(NextFrame, GetClientUserId(iEntity));
}

public void NextFrame(int iUserID)// don't identity fix bots that die and respawn just find least used survivor
{
	int iClient = GetClientOfUserId(iUserID);
	
	if(iClient < 1 || !IsClientInGame(iClient))
		return;
	
	if(bShouldIgnoreOnce[iClient])
	{
		bShouldIgnoreOnce[iClient] = false;
		return;
	}
	SetCharacter(iClient);
}

//set iclient to 0 to not ignore, for anyone using this function
int CheckLeastUsedSurvivor(int iClient)
{
	int iLeastChar[8];
	int iCharBuffer;
	int i;
	for(i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || GetClientTeam(i) != 2 || i == iClient)
			continue;
		
		if(iSurvivorSet != L4D2_SurvivorSet_L4D2)
		{
			if((iCharBuffer = GetEntProp(i, Prop_Send, "m_survivorCharacter", 2)) > 7)//in SpawnPost the entprop is 8, because valve wants it to be 8 at this point
				continue;
		}
		else
			if((iCharBuffer = GetEntProp(i, Prop_Send, "m_survivorCharacter", 2)) > 3)
				continue;
		
		
		iLeastChar[iCharBuffer]++;
	}
	
	int iSurvivorCharIndex = iLeastChar[0];
	iCharBuffer = 0;
	int iNum;
	if(iSurvivorSet == L4D2_SurvivorSet_L4D2 || (iSurvivorSet == L4D2_SurvivorSet_Default && iCurrentSet == L4D2_SurvivorSet_L4D2)) 
	{
		iNum = 3;
	}
	else
		iNum = 7;
	
	for(i = 0; i <= iNum; i++)
	{
		if(iLeastChar[i] < iSurvivorCharIndex)
		{
			iSurvivorCharIndex = iLeastChar[i];
			iCharBuffer = i;
		}
	}
	return iCharBuffer;
}

void SetCharacter(int iClient)
{
	L4D2_SurvivorSet iSetCheck;
	if(iSurvivorSet == L4D2_SurvivorSet_Default)
		iSetCheck = iCurrentSet;
	else
		iSetCheck = iSurvivorSet;
	
	switch(iSetCheck)
	{
		case L4D2_SurvivorSet_L4D1:
		{
			switch(CheckLeastUsedSurvivor(iClient))
			{
				case 0:
					SetCharacterInfo(iClient, L4D1_SETINDEX_BILL_1);
				case 1:
					SetCharacterInfo(iClient, L4D1_SETINDEX_ZOEY_1);
				case 2:
					SetCharacterInfo(iClient, L4D1_SETINDEX_LOUIS_1);
				case 3:
					SetCharacterInfo(iClient, L4D1_SETINDEX_FRANCIS_1);
				case 4:
					SetCharacterInfo(iClient, L4D1_SETINDEX_BILL_2);
				case 5:
					SetCharacterInfo(iClient, L4D1_SETINDEX_ZOEY_2);
				case 6:
					SetCharacterInfo(iClient, L4D1_SETINDEX_FRANCIS_2);
				case 7:
					SetCharacterInfo(iClient, L4D1_SETINDEX_LOUIS_2);
				
			}
		}
		case L4D2_SurvivorSet_L4D2, L4D2_SurvivorSet_Both:
		{
			switch(CheckLeastUsedSurvivor(iClient))
			{
				case 0:
					SetCharacterInfo(iClient, L4D2_SETINDEX_NICK);
				case 1:
					SetCharacterInfo(iClient, L4D2_SETINDEX_ROCHELLE);
				case 2:
					SetCharacterInfo(iClient, L4D2_SETINDEX_COACH);
				case 3:
					SetCharacterInfo(iClient, L4D2_SETINDEX_ELLIS);
				case 4:
					SetCharacterInfo(iClient, L4D2_SETINDEX_BILL);
				case 5:
					SetCharacterInfo(iClient, L4D2_SETINDEX_ZOEY);
				case 6:
					SetCharacterInfo(iClient, L4D2_SETINDEX_FRANCIS);
				case 7:
					SetCharacterInfo(iClient, L4D2_SETINDEX_LOUIS);
				
			}
		}
	}
}

void SetCharacterInfo(int iClient, int iCharIndex, int iModelIndex)
{
	SetEntProp(iClient, Prop_Send, "m_survivorCharacter", iCharIndex, 2);
	SetEntityModel(iClient, sSurvivorModels[iModelIndex]);
	SetClientInfo(iClient, "name", sSurvivorNames[iModelIndex]);
}

public MRESReturn Detour_OnGetSurvivorSet(Handle hReturn)
{
	// Store the return value
	iCurrentSet = DHookGetReturn(hReturn);
	if(iSurvivorSet == L4D2_SurvivorSet_Default)
		return MRES_Ignored;
	
	if(iSurvivorSet == L4D2_SurvivorSet_Both || iSurvivorSet == L4D2_SurvivorSet_L4D2)
	{
		iCurrentSet = L4D2_SurvivorSet_L4D2;
		DHookSetReturn(hReturn, L4D2_SurvivorSet_L4D2);
		return MRES_Supercede;
	}
	iCurrentSet = L4D2_SurvivorSet_L4D1;
	DHookSetReturn(hReturn, L4D2_SurvivorSet_L4D1);
	return MRES_Supercede;
}
