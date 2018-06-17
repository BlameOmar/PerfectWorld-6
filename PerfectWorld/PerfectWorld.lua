--------------------------------------------------------------------------------
-- PerfectWorld 6 Map Script
-- Version 6.1
--
-- Original script by Rich Marinaccio
-- Updated with contributions by:
--   Bobert13
--   LamilLerran
--   Omar Stefan Evans A.K.A. BlameOmar
--
-- PerfectWorld 6 is a Civilization 6 port of the PerfectWorld3 (version 5b) map
-- script, which was written by Rich Marinaccio for Civilization 5 and updated
-- by Bobert13 of the CivFanatics Forums (https://forums.civfanatics.com).
-- This port also includes code from the Planet Simulator (version LL3) map
-- script, which was written by Bobert13 for Civilization 5 based on his work,
-- for PerfectWorld3, and updated by LamilLerran, also of the CivFanatics
-- Forums.
--
-- This map script uses various manipulations of Perlin noise to create
-- landforms, and generates climate based on a simplified model of geostrophic
-- and monsoon wind patterns. Rivers are generated along accurate drainage paths
-- governed by the elevation map used to create the landforms.
--
-- Version History
--   6.1 - Ported to Civilization 6!
--         Adjusted maps constants.
--         World age, temperature, rainfall, and sea level are configurable via advanced options.
--
--   5b  - Fixed and Optimized SiltifyLakes(). Purged the first random number after seeding.
--
--   5a  - Fixed the possibility rivers that can't path to a body of water. Minor bugfixes.
--		   Adjusted YtoX Ratio used in landmass generation.
--
--   5   - Highly optimized with fixes ranging from Oasis placement to crashes.
--
--   4   - A working version of v3
--
--   3   - Placed Atolls. Shrank the huge map size based on advice from Sirian.
--
--   2   - Shrank the map sizes except for huge. Added a better way to adjust river
--         lengths. Used the continent art styles in a more diverse way. Cleaned up the
--         mountain ranges a bit.
--
--   1   - Initial release! 2010-11-24
--------------------------------------------------------------------------------

include "MapEnums"
include "MapUtilities"
include "NaturalWonderGenerator"
include "ResourceGenerator"
include "AssignStartingPlots"

local g_NameString = "PerfectWorld"
local g_VersionString = "6.1"
local g_RunTests = true

function PW_NameAndVersionString()
	return "[" .. g_NameString .. " " .. g_VersionString .. "]"
end

function PW_Log(message)
	print(PW_NameAndVersionString() .. ": " .. message)
end

-- Test suites will be run if g_RunTests == true.
PW_Tests = {}

--------------------------------------------------------------------------------
-- The entry point into the map script.
--------------------------------------------------------------------------------
local g_Width, g_Height
local g_PlotTypesMap
local g_TerrainTypesMap
function GenerateMap()
	if g_RunTests then PW_RunAllTests() end

	PW_Log("Generating Map")
	local time = os.clock()

	-- Set globals
	g_Width, g_Height = Map.GetGridSize()
	g_PlotTypesMap = PW_RectMap:New(g_Width, g_Height, true, true, g_PLOT_TYPE_NONE)
	g_TerrainTypesMap = PW_RectMap:New(g_Width, g_Height, true, true, g_TERRAIN_TYPE_NONE)

	PWRandSeed()
	PWGeneratePlotTypes()
	PWGenerateTerrainTypes()
	ApplyTerrain(g_PlotTypesMap, g_TerrainTypesMap)
	AddRivers()
	AddFeatures()
	-- Cleanup()

--	local args = {
--		numberToPlace = GameInfo.Maps[Map.GetMapSize()].NumNaturalWonders,
--	};
--	local nwGen = NaturalWonderGenerator.Create(args);

	AreaBuilder.Recalculate()
	TerrainBuilder.AnalyzeChokepoints()
	TerrainBuilder.StampContinents()

	resourcesConfig = MapConfiguration.GetValue("resources");
	local startConfig = MapConfiguration.GetValue("start");-- Get the start config
	local args = {
		resources = resourcesConfig,
		START_CONFIG = startConfig,
	};
	local resGen = ResourceGenerator.Create(args);

	print("Creating start plot database.");
	
	-- START_MIN_Y and START_MAX_Y is the percent of the map ignored for major civs' starting positions.
	local args = {
		MIN_MAJOR_CIV_FERTILITY = 150,
		MIN_MINOR_CIV_FERTILITY = 50, 
		MIN_BARBARIAN_FERTILITY = 1,
		START_MIN_Y = 15,
		START_MAX_Y = 15,
		START_CONFIG = startConfig,
	};
	local start_plot_database = AssignStartingPlots.Create(args)

	local GoodyGen = AddGoodies(g_Width, g_Height);
	PW_Log(string.format("Generated map in %.3f seconds.", os.clock() - time))
end
--------------------------------------------------------------------------------
-- Map Constants and Parameters
--------------------------------------------------------------------------------
MapConstants = {}
function MapConstants:New()
	local mconst = {}
	setmetatable(mconst, self)
	self.__index = self

	-------------------------------------------------------------------------------------------
	--Landmass constants
	-------------------------------------------------------------------------------------------
	--(Moved)mconst.landPercent = 0.31       --Now in InitializeSeaLevel()
	--(Moved)mconst.hillsPercent = 0.70      --Now in InitializeWorldAge()
	--(Moved)mconst.mountainsPercent = 0.94  --Now in InitializeWorldAge()
	mconst.mountainWeight = 0.7		--Weight of the mountain elevation map versus the coastline elevation map.
	
	--Adjusting these frequences will generate larger or smaller landmasses and features. Default frequencies for map of width 128.
	mconst.twistMinFreq = 0.02 		--Recommended range:[0.02 to 0.1] Lower values result in more blob-like landmasses, higher values make more stringy landmasses, even higher values results in lots and lots of islands.
	mconst.twistMaxFreq = 0.12		--Recommended range:[0.03 to 0.3] Lower values result in Pangeas, higher values makes continental divisions and stringy features more likely, and very high values  result in a lot of stringy continents and islands.
	mconst.twistVar = 0.042			--Recommended range:[0.01 to 0.3] Determines the deviation range in elevation from one plot to another. Low values result in regular landmasses with few islands, higher values result in more islands and more variance on landmasses and coastlines.
	mconst.mountainFreq = 0.078		--Recommended range:[0.1 to 0.8] Lower values make large, long, mountain ranges. Higher values make sporadic mountainous features.
	
	--These attenuation factors lower the altitude of the map edges. This is currently used to prevent large continents in the uninhabitable polar regions.
	mconst.northAttenuationFactor = 0.85
	mconst.northAttenuationRange = 0.08 --percent of the map height.
	mconst.southAttenuationFactor = 0.85
	mconst.southAttenuationRange = 0.08 --percent of the map height.

	--East/west attenuation is set to zero, but modded maps may have need for them.
	mconst.eastAttenuationFactor = 0.0
	mconst.eastAttenuationRange = 0.0 --percent of the map width.
	mconst.westAttenuationFactor = 0.0
	mconst.westAttenuationRange = 0.0 --percent of the map width.
	
	--Hex maps are shorter in the y direction than they are wide per unit by this much. We need to know this to sample the perlin maps properly so they don't look squished.
	local W,H = Map.GetGridSize()
	mconst.YtoXRatio = math.sqrt(W/H)
	-------------------------------------------------------------------------------------------
	--Terrain type constants
	-------------------------------------------------------------------------------------------
	--(Moved)mconst.desertPercent = 0.25         --Now in InitializeRainfall()
	--(Moved)mconst.desertMinTemperature = 0.35  --Now in InitializeTemperature()
	--(Moved)mconst.plainsPercent = 0.50         --Now in InitializeRainfall()
	--(Moved)mconst.tundraTemperature = 0.31     --Now in InitializeTemperature()
	--(Moved)mconst.snowTemperature = 0.26       --Now in InitializeTemperature()
	mconst.simpleCleanup = true		--Turns parts of the terrain matching function on or off. 
	-------------------------------------------------------------------------------------------
	--Terrain feature constants
	-------------------------------------------------------------------------------------------
	--(Moved)mconst.zeroTreesPercent = 0.70      --Now in InitializeRainfall()
	--(Moved)mconst.treesMinTemperature = 0.28   --Now in InitializeTemperature()

	--(Moved)mconst.junglePercent = 0.88         --Now in InitializeRainfall()
	--(Moved)mconst.jungleMinTemperature = 0.66  --Now in InitializeTemperature()

	--(Moved)mconst.riverPercent = 0.18          --Now in InitializeRainfall()
	--(Moved)mconst.riverRainCheatFactor = 1.6   --Now in InitializeRainfall()
	--(Moved)mconst.minRiverSize = 24            --Now in InitializeRainfall()
	
	--(Moved)mconst.marshElevation = 0.07 	     --Now in InitializeRainfall()
	
	mconst.OasisThreshold = 7 		--Maximum fertility around a tile for it to be considered for an Oasis -Bobert13
	
	--(Moved)mconst.iceNorthLatitudeLimit = 63   --Now in InitializeTemperature()
	--(Moved)mconst.iceSouthLatitudeLimit = -63  --Now in InitializeTemperature()
	-------------------------------------------------------------------------------------------
	--Weather constants
	-------------------------------------------------------------------------------------------
	--Important latitude markers used for generating climate.
	mconst.polarFrontLatitude = 65
	mconst.tropicLatitudes = 23
	mconst.horseLatitudes = 31
	mconst.topLatitude = 70
	mconst.bottomLatitude = -mconst.topLatitude

	--These set the water temperature compression that creates the land/sea seasonal temperature differences that cause monsoon winds.
	mconst.minWaterTemp = 0.10
	mconst.maxWaterTemp = 0.50

	--Strength of geostrophic climate generation versus monsoon climate generation.
	mconst.geostrophicFactor = 3.0
	mconst.geostrophicLateralWindStrength = 0.4

	--Crazy rain tweaking variables. I wouldn't touch these if I were you.
	mconst.minimumRainCost = 0.0001
	mconst.upLiftExponent = 4
	mconst.polarRainBoost = 0.08
	mconst.pressureNorm = 0.90 --[1.0 = no normalization] Helps to prevent exaggerated Jungle/Marsh banding on the equator. -Bobert13

	--#######################################################################################--
	--Below are map constants that should not be altered.
	--#######################################################################################--
	
	--directions
	mconst.C = 0
	mconst.W = 1
	mconst.NW = 2
	mconst.NE = 3
	mconst.E = 4
	mconst.SE = 5
	mconst.SW = 6

	--flow directions
	mconst.NOFLOW = 0
	mconst.WESTFLOW = 1
	mconst.EASTFLOW = 2
	mconst.VERTFLOW = 3

	--wind zones
	mconst.NOZONE = -1
	mconst.NPOLAR = 0
	mconst.NTEMPERATE = 1
	mconst.NEQUATOR = 2
	mconst.SEQUATOR = 3
	mconst.STEMPERATE = 4
	mconst.SPOLAR = 5

	mconst:InitializeSeaLevel()
	mconst:InitializeWorldAge()
	mconst:InitializeTemperature()
	mconst:InitializeRainfall()

	return mconst
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeWorldAge()
	local age = MapConfiguration.GetValue("world_age")
	if age == 4 then
		age = 1 + TerrainBuilder.GetRandomNumber(3, "Random World Age - PerfectWorld")
	end
	if age == 1 then		--Young
		PW_Log("Setting young world constants")
		self.hillsPercent = 0.65	
		self.mountainsPercent = 0.90
	elseif age == 3 then	--Old
		PW_Log("Setting old world constants")
		self.hillsPercent = 0.74 		
		self.mountainsPercent = 0.97 		
	else									--Standard
		PW_Log("Setting middle aged world constants")
		self.hillsPercent = 0.70 		--Percent of dry land that is below the hill elevation deviance threshold.		
		self.mountainsPercent = 0.94	--Percent of dry land that is below the mountain elevation deviance threshold. 	
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeTemperature()
	local temp =  MapConfiguration.GetValue("temperature")
	if temp == 4 then
		temp = 1 + TerrainBuilder.GetRandomNumber(3, "Random World Temperature Option - PerfectWorld");
	end
	if temp == 1 then						--Cold
		PW_Log("Setting cold world constants")
		self.desertMinTemperature = 0.65
		self.tundraTemperature = 0.35
		self.snowTemperature = 0.20
		
		self.treesMinTemperature = 0.30
		self.jungleMinTemperature = 0.75

		self.iceNorthLatitudeLimit = 60
		self.iceSouthLatitudeLimit = -60
	elseif temp == 3 then					--Warm
		PW_Log("Setting warm world constants")
		self.desertMinTemperature = 0.55
		self.tundraTemperature = 0.26
		self.snowTemperature = 0.10
		
		self.treesMinTemperature = 0.21
		self.jungleMinTemperature = 0.60

		self.iceNorthLatitudeLimit = 65
		self.iceSouthLatitudeLimit = -65
	else									--Standard
		PW_Log("Setting temperate world constants")
		self.desertMinTemperature = 0.60	--Coldest absolute temperature allowed to be desert, plains if colder.
		self.tundraTemperature = 0.31		--Absolute temperature below which is tundra.
		self.snowTemperature = 0.15 		--Absolute temperature below which is snow.
		
		self.treesMinTemperature = 0.27		--Coldest absolute temperature where trees appear.
		self.jungleMinTemperature = 0.66	--Coldest absolute temperature allowed to be jungle, forest if colder.

		self.iceNorthLatitudeLimit = 63		--Northern Ice latitude limit.
		self.iceSouthLatitudeLimit = -63	--Southern Ice latitude limit.
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeRainfall()
	local rain = MapConfiguration.GetValue("rainfall")
	if rain == 4 then
		rain = 1 + TerrainBuilder.GetRandomNumber(3, "Random World Rainfall Option - PerfectWorld");
	end
	if rain == 1 then					--Arid
		PW_Log("Setting arid world constants")
		self.desertPercent = 0.33
		self.plainsPercent = 0.55
		self.zeroTreesPercent = 0.36
		self.junglePercent = 0.94
		
		self.riverPercent = 0.14
		self.riverRainCheatFactor = 1.2
		self.minRiverSize = 32
		self.marshElevation = 0.04
	elseif rain == 3 then				--Wet
		PW_Log("Setting wet world constants")
		self.desertPercent = 0.20
		self.plainsPercent = 0.45
		self.zeroTreesPercent = 0.23
		self.junglePercent = 0.80
		
		self.riverPercent = 0.25
		self.riverRainCheatFactor = 1.6
		self.minRiverSize = 16
		self.marshElevation = 0.10
	else								--Standard
		PW_Log("Setting normal rainfall constants")
		self.desertPercent = 0.25		--Percent of land that is below the desert rainfall threshold.
		self.plainsPercent = 0.50 		--Percent of land that is below the plains rainfall threshold.
		self.zeroTreesPercent = 0.28 	--Percent of land that is below the rainfall threshold where no trees can appear.
		self.junglePercent = 0.88 		--Percent of land below the jungle rainfall threshold.
		
		self.riverPercent = 0.18 		--percent of river junctions that are large enough to become rivers.
		self.riverRainCheatFactor = 1.6 --This value is multiplied by each river step. Values greater than one favor watershed size. Values less than one favor actual rain amount.
		self.minRiverSize = 24			--Helps to prevent a lot of really short rivers. Recommended values are 15 to 40. -Bobert13
		self.marshElevation = 0.07 		--Percent of land below the lowlands marsh threshold.
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeSeaLevel()
	local sea_level_low = 63
	local sea_level_normal = 69
	local sea_level_high = 75

	local sea_level = MapConfiguration.GetValue("sea_level");
	
	local water_percent
	if sea_level == 1 then -- Low Sea Level
		PW_Log("Setting low sea level")
		water_percent = sea_level_low
	elseif sea_level == 2 then -- Normal Sea Level
		PW_Log("Setting normal sea level")
		water_percent = sea_level_normal
	elseif sea_level == 3 then -- High Sea Level
		PW_Log("Setting high sea level")
		water_percent = sea_level_high
	else
		water_percent = TerrainBuilder.GetRandomNumber(sea_level_high - sea_level_low, "Random Sea Level - PerfectWorld") + sea_level_low + 1
	end

	self.landPercent = (100 - water_percent) / 100
end
-------------------------------------------------------------------------------------------

function ApplyTerrainToPlot(plot, plot_type, terrain_type)
	if (plot_type == g_PLOT_TYPE_HILLS) then
		terrain_type = terrain_type + g_TERRAIN_BASE_TO_HILLS_DELTA
	elseif (plot_type == g_PLOT_TYPE_MOUNTAIN) then
		terrain_type = terrain_type + g_TERRAIN_BASE_TO_MOUNTAIN_DELTA
	end

	TerrainBuilder.SetTerrainType(plot, terrain_type)
end

function ApplyTerrain(plotTypes, terrainTypes)
	for i = 0, (g_Width * g_Height) - 1, 1 do
		local pPlot = Map.GetPlotByIndex(i);
		local x, y = g_PlotTypesMap:DeprecatedGetIndexForDataIndex(i)

		local plot_type = g_PlotTypesMap:Get(x, y)
		local terrain_type = g_TerrainTypesMap:Get(x, y)

		ApplyTerrainToPlot(pPlot, plot_type, terrain_type)
	end
end

local g_ElevationMap
local g_RiverMap
--Global lookup tables used to track land, and terrain type. Used throughout terrain placement, Cleanup, and feature placement. -Bobert13
local g_DesertTab = {}
local g_SnowTab = {}
local g_TundraTab = {}
local g_PlainsTab = {}
local g_GrassTab = {}
local g_LandTab = {}
function PWGeneratePlotTypes()
	-- This function uses lots of globals.

	PW_Log("Creating initial map data")
	local W,H = Map.GetGridSize()
	--first do all the preliminary calculations in this function
	PW_Log(string.format("Map size: width=%d, height=%d",W,H))
	mc = MapConstants:New()

	g_ElevationMap = GenerateElevationMap(W,H,true,false)
	--g_ElevationMap:Save("g_ElevationMap.csv")
	
	FillInLakes()

	--now gen plot types
	PW_Log("Generating plot types")
	ShiftMaps();

	DiffMap = GenerateDiffMap(W,H,true,false);

	--find exact thresholds
	local hillsThreshold = DiffMap:FindThresholdFromPercent(mc.hillsPercent,false,true)
	local mountainsThreshold = DiffMap:FindThresholdFromPercent(mc.mountainsPercent,false,true)
	local mountainTab = {}
	local i = 0
	for y = 0, H - 1,1 do
		for x = 0,W - 1,1 do
			if g_ElevationMap:IsBelowSeaLevel(x,y) then
				g_PlotTypesMap:Reset(x, y, g_PLOT_TYPE_OCEAN)
			elseif DiffMap.data[i] < hillsThreshold then
				g_PlotTypesMap:Reset(x, y, g_PLOT_TYPE_LAND)
				table.insert(g_LandTab,i)
			elseif DiffMap.data[i] < mountainsThreshold then
				g_PlotTypesMap:Reset(x, y, g_PLOT_TYPE_HILLS)
				table.insert(g_LandTab,i)
			else
				g_PlotTypesMap:Reset(x, y, g_PLOT_TYPE_MOUNTAIN)
				table.insert(g_LandTab,i)
				table.insert(mountainTab,i)
			end
			i=i+1
		end
	end

	-- Gets rid of single tile mountains in the oceans. -- Bobert13
	for k = 1,#mountainTab,1 do
		local i = mountainTab[k]
		local tiles = GetSpiral(i,1)
		local landCount = 0
		for n=1,#tiles do
			local ii = tiles[n]
			if ii~= -1 then
				local x, y = g_PlotTypesMap:DeprecatedGetIndexForDataIndex(ii)
				local plot_type = g_PlotTypesMap:Get(x, y)
				if plot_type == g_PLOT_TYPE_HILLS or plot_type == g_PLOT_TYPE_LAND then
					landCount = landCount + 1
				end
			end
		end
		if landCount == 0 then
			local roll1 = PWRandInt(1,3)
			local x, y = g_PlotTypesMap:DeprecatedGetIndexForDataIndex(i)
			if roll1 == 1 then
				g_PlotTypesMap:Reset(x, y, g_PLOT_TYPE_LAND)
			else
				g_PlotTypesMap:Reset(x, y, g_PLOT_TYPE_HILLS)
			end
		end
	end
	
	g_RainfallMap, g_TemperatureMap = GenerateRainfallMap(g_ElevationMap)
	--g_RainfallMap:Save("g_RainfallMap.csv")

	g_RiverMap = RiverMap:New(g_ElevationMap)
	g_RiverMap:SetJunctionAltitudes()
	g_RiverMap:SiltifyLakes()
	g_RiverMap:SetFlowDestinations()
	g_RiverMap:SetRiverSizes(g_RainfallMap)

	-- I'm not sure where this is defined yet.
	-- GenerateCoasts();
end

function PWGenerateTerrainTypes()
	PW_Log("Generating terrain")
	local W, H = Map.GetGridSize();
	--first find minimum rain above sea level for a soft desert transition
	local minRain = math.huge
	for i = 0, W * H - 1 do
		local x, y = g_PlotTypesMap:DeprecatedGetIndexForDataIndex(i)
		local plot_type = g_PlotTypesMap:Get(x, y)
		if plot_type ~= g_PLOT_TYPE_OCEAN then
			if g_RainfallMap.data[i] < minRain then
				minRain = g_RainfallMap.data[i]
			end
		end
	end

	--find exact thresholds
	-- TODO(omar): Make coast generation less magical.
	local coastsThreshold = g_ElevationMap:FindThresholdFromPercent(0.4, false, false)
	local desertThreshold = g_RainfallMap:FindThresholdFromPercent(mc.desertPercent,false,true)
	local plainsThreshold = g_RainfallMap:FindThresholdFromPercent(mc.plainsPercent,false,true)

	for i = 0, W * H - 1 do
		local x, y = g_PlotTypesMap:DeprecatedGetIndexForDataIndex(i)
		local plot_type = g_PlotTypesMap:Get(x, y)
		if plot_type == g_PLOT_TYPE_OCEAN then
			if g_ElevationMap.data[i] < coastsThreshold then
				g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_OCEAN)
			else
				g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_COAST)
			end
		else -- Land
			if g_TemperatureMap.data[i] < mc.snowTemperature then
				g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_SNOW)
				table.insert(g_SnowTab,i)
			elseif g_TemperatureMap.data[i] < mc.tundraTemperature then
				g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_TUNDRA)
				table.insert(g_TundraTab,i)
			elseif g_RainfallMap.data[i] < desertThreshold then
				if g_TemperatureMap.data[i] < mc.desertMinTemperature then
					g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_PLAINS)
					table.insert(g_PlainsTab,i)
				else
					g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_DESERT)
					table.insert(g_DesertTab,i)
				end
			elseif g_RainfallMap.data[i] < plainsThreshold then
				if g_RainfallMap.data[i] < (PWRand() * (plainsThreshold - desertThreshold) + plainsThreshold - desertThreshold)/2.0 + desertThreshold then
					g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_PLAINS)
					table.insert(g_PlainsTab,i)
				else
					g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_GRASS)
					table.insert(g_GrassTab,i)
				end
			else
				g_TerrainTypesMap:Reset(x, y, g_TERRAIN_TYPE_GRASS)
				table.insert(g_GrassTab,i)
			end
		end
	end
end
-----------------------------------------------------------------------------
--Interpolation and Perlin functions
-----------------------------------------------------------------------------
function CubicInterpolate(v0,v1,v2,v3,mu)
	local mu2 = mu * mu
	local a0 = v3 - v2 - v0 + v1
	local a1 = v0 - v1 - a0
	local a2 = v2 - v0
	local a3 = v1

	return (a0 * mu * mu2 + a1 * mu2 + a2 * mu + a3)
end
-------------------------------------------------------------------------------------------
function BicubicInterpolate(v,muX,muY)
	local a0 = CubicInterpolate(v[1],v[2],v[3],v[4],muX);
	local a1 = CubicInterpolate(v[5],v[6],v[7],v[8],muX);
	local a2 = CubicInterpolate(v[9],v[10],v[11],v[12],muX);
	local a3 = CubicInterpolate(v[13],v[14],v[15],v[16],muX);

	return CubicInterpolate(a0,a1,a2,a3,muY)
end
-------------------------------------------------------------------------------------------
function CubicDerivative(v0,v1,v2,v3,mu)
	local mu2 = mu * mu
	local a0 = v3 - v2 - v0 + v1
	local a1 = v0 - v1 - a0
	local a2 = v2 - v0
	--local a3 = v1

	return (3 * a0 * mu2 + 2 * a1 * mu + a2)
end
-------------------------------------------------------------------------------------------
function BicubicDerivative(v,muX,muY)
	local a0 = CubicInterpolate(v[1],v[2],v[3],v[4],muX);
	local a1 = CubicInterpolate(v[5],v[6],v[7],v[8],muX);
	local a2 = CubicInterpolate(v[9],v[10],v[11],v[12],muX);
	local a3 = CubicInterpolate(v[13],v[14],v[15],v[16],muX);

	return CubicDerivative(a0,a1,a2,a3,muY)
end
-------------------------------------------------------------------------------------------
--This function gets a smoothly interpolated value from srcMap.
--x and y are non-integer coordinates of where the value is to
--be calculated, and wrap in both directions. srcMap is an object
--of type FloatMap.
function GetInterpolatedValue(X,Y,srcMap)
	local points = {}
	local fractionX = X - math.floor(X)
	local fractionY = Y - math.floor(Y)

	--wrappedX and wrappedY are set to -1,-1 of the sampled area
	--so that the sample area is in the middle quad of the 4x4 grid
	local wrappedX = ((math.floor(X) - 1) % srcMap.rectWidth) + srcMap.rectX
	local wrappedY = ((math.floor(Y) - 1) % srcMap.rectHeight) + srcMap.rectY

	local x
	local y

	for pY = 0, 4-1,1 do
		y = pY + wrappedY
		for pX = 0,4-1,1 do
			x = pX + wrappedX
			local srcIndex = srcMap:GetRectIndex(x,y)
			points[(pY * 4 + pX) + 1] = srcMap.data[srcIndex]
		end
	end

	local finalValue = BicubicInterpolate(points,fractionX,fractionY)

	return finalValue

end
-------------------------------------------------------------------------------------------
function GetDerivativeValue(X,Y,srcMap)
	local points = {}
	local fractionX = X - math.floor(X)
	local fractionY = Y - math.floor(Y)

	--wrappedX and wrappedY are set to -1,-1 of the sampled area
	--so that the sample area is in the middle quad of the 4x4 grid
	local wrappedX = ((math.floor(X) - 1) % srcMap.rectWidth) + srcMap.rectX
	local wrappedY = ((math.floor(Y) - 1) % srcMap.rectHeight) + srcMap.rectY

	local x
	local y

	for pY = 0, 4-1,1 do
		y = pY + wrappedY
		for pX = 0,4-1,1 do
			x = pX + wrappedX
			local srcIndex = srcMap:GetRectIndex(x,y)
			points[(pY * 4 + pX) + 1] = srcMap.data[srcIndex]
		end
	end

	local finalValue = BicubicDerivative(points,fractionX,fractionY)

	return finalValue

end
-------------------------------------------------------------------------------------------
--This function gets Perlin noise for the destination coordinates. Note
--that in order for the noise to wrap, the area sampled on the noise map
--must change to fit each octave.
function GetPerlinNoise(x,y,destMapWidth,destMapHeight,initialFrequency,initialAmplitude,amplitudeChange,octaves,noiseMap)
	local finalValue = 0.0
	local frequency = initialFrequency
	local amplitude = initialAmplitude
	local frequencyX --slight adjustment for seamless wrapping
	local frequencyY --''
	for i = 1,octaves,1 do
		if noiseMap.wrapX then
			noiseMap.rectX = math.floor(noiseMap.width/2 - (destMapWidth * frequency)/2)
			noiseMap.rectWidth = math.max(math.floor(destMapWidth * frequency),1)
			frequencyX = noiseMap.rectWidth/destMapWidth
		else
			noiseMap.rectX = 0
			noiseMap.rectWidth = noiseMap.width
			frequencyX = frequency
		end
		if noiseMap.wrapY then
			noiseMap.rectY = math.floor(noiseMap.height/2 - (destMapHeight * frequency)/2)
			noiseMap.rectHeight = math.max(math.floor(destMapHeight * frequency),1)
			frequencyY = noiseMap.rectHeight/destMapHeight
		else
			noiseMap.rectY = 0
			noiseMap.rectHeight = noiseMap.height
			frequencyY = frequency
		end

		finalValue = finalValue + GetInterpolatedValue(x * frequencyX, y * frequencyY, noiseMap) * amplitude
		frequency = frequency * 2.0
		amplitude = amplitude * amplitudeChange
	end
	finalValue = finalValue/octaves
	return finalValue
end
-------------------------------------------------------------------------------------------
function GetPerlinDerivative(x,y,destMapWidth,destMapHeight,initialFrequency,initialAmplitude,amplitudeChange,octaves,noiseMap)
	local finalValue = 0.0
	local frequency = initialFrequency
	local amplitude = initialAmplitude
	local frequencyX --slight adjustment for seamless wrapping
	local frequencyY --''
	for i = 1,octaves,1 do
		if noiseMap.wrapX then
			noiseMap.rectX = math.floor(noiseMap.width/2 - (destMapWidth * frequency)/2)
			noiseMap.rectWidth = math.floor(destMapWidth * frequency)
			frequencyX = noiseMap.rectWidth/destMapWidth
		else
			noiseMap.rectX = 0
			noiseMap.rectWidth = noiseMap.width
			frequencyX = frequency
		end
		if noiseMap.wrapY then
			noiseMap.rectY = math.floor(noiseMap.height/2 - (destMapHeight * frequency)/2)
			noiseMap.rectHeight = math.floor(destMapHeight * frequency)
			frequencyY = noiseMap.rectHeight/destMapHeight
		else
			noiseMap.rectY = 0
			noiseMap.rectHeight = noiseMap.height
			frequencyY = frequency
		end

		finalValue = finalValue + GetDerivativeValue(x * frequencyX, y * frequencyY, noiseMap) * amplitude
		frequency = frequency * 2.0
		amplitude = amplitude * amplitudeChange
	end
	finalValue = finalValue/octaves
	return finalValue
end
-------------------------------------------------------------------------------------------
function Push(a,item)
	table.insert(a,item)
end
-------------------------------------------------------------------------------------------
function Pop(a)
	return table.remove(a)
end
------------------------------------------------------------------------
--inheritance mechanism from http://www.gamedev.net/community/forums/topic.asp?topic_id=561909
------------------------------------------------------------------------
function inheritsFrom( baseClass )

    local new_class = {}
    local class_mt = { __index = new_class }

    function new_class:create()
        local newinst = {}
        setmetatable( newinst, class_mt )
        return newinst
    end

    if nil ~= baseClass then
        setmetatable( new_class, { __index = baseClass } )
    end

    -- Implementation of additional OO properties starts here --

    -- Return the class object of the instance
    function new_class:class()
        return new_class;
    end

	-- Return the super class object of the instance, optional base class of the given class (must be part of hiearchy)
    function new_class:baseClass(class)
		return new_class:_B(class);
    end

    -- Return the super class object of the instance, optional base class of the given class (must be part of hiearchy)
    function new_class:_B(class)
		if (class==nil) or (new_class==class) then
			return baseClass;
		elseif(baseClass~=nil) then
			return baseClass:_B(class);
		end
		return nil;
    end

	-- Return true if the caller is an instance of theClass
    function new_class:_ISA( theClass )
        local b_isa = false

        local cur_class = new_class

        while ( nil ~= cur_class ) and ( false == b_isa ) do
            if cur_class == theClass then
                b_isa = true
            else
                cur_class = cur_class:baseClass()
            end
        end

        return b_isa
    end

    return new_class
end
-------------------------------------------------------------------------------------------
-- Random functions will use lua rands for stand alone script running
-- and Map.rand for in game.
-------------------------------------------------------------------------------------------
function PWRand()
	return math.random()
end
-------------------------------------------------------------------------------------------
function PWRandSeed(fixedseed)
	local seed
	if fixedseed == nil then
		seed = (TerrainBuilder.GetRandomNumber(32767,"") * 65536) +TerrainBuilder.GetRandomNumber(65535,"")  --This function caps at this number, if you set it any higher, or try to trick it with multiple RNGs that end up with a value above this, it will break randomization. This is 31 bits of precision so... - Bobert13
	else
		seed = fixedseed
	end
	math.randomseed(seed)
	print("Random seed for this map is " .. seed.." - PerfectWorld3")
	
	PWRand() --Trash the first random to (hopefully) ensure we roll the same exact map given the same seed.
end
-------------------------------------------------------------------------------------------
--range is inclusive, low and high are possible results
function PWRandInt(low, high)
	return math.random(low, high)
end
-------------------------------------------------------------------------------------------
-- FloatMap class
-- This is for storing 2D map data. The 'data' field is a zero based, one
-- dimensional array. To access map data by x and y coordinates, use the
-- GetIndex method to obtain the 1D index, which will handle any needs for
-- wrapping in the x and y directions.
-------------------------------------------------------------------------------------------
FloatMap = inheritsFrom(nil)

function FloatMap:New(width, height, wrapX, wrapY)
	local new_inst = {}
	setmetatable(new_inst, {__index = FloatMap});	--setup metatable

	new_inst.width = width
	new_inst.height = height
	new_inst.wrapX = wrapX
	new_inst.wrapY = wrapY
	new_inst.length = width*height

	--These fields are used to access only a subset of the map
	--with the GetRectIndex function. This is useful for
	--making Perlin noise wrap without generating separate
	--noise fields for each octave
	new_inst.rectX = 0
	new_inst.rectY = 0
	new_inst.rectWidth = width
	new_inst.rectHeight = height

	new_inst.data = {}
	for i = 0,width*height - 1,1 do
		new_inst.data[i] = 0.0
	end

	return new_inst
end
-------------------------------------------------------------------------------------------
function FloatMap:GetNeighbor(x,y,dir)
	local xx
	local yy
	local odd = y % 2
	if dir == mc.C then
		return x,y
	elseif dir == mc.W then
		if x == 0 and self.wrapX then
			xx = self.width-1
			yy = y
		else
			xx = x - 1
			yy = y
		end
		return xx,yy
	elseif dir == mc.NW then
		if x == 0 and odd == 0 and self.wrapX then
			xx = self.width-1
			yy = y + 1
		else
			xx = x - 1 + odd
			yy = y + 1
		end
		return xx,yy
	elseif dir == mc.NE then
		if x == self.width-1 and odd == 1 and self.wrapX then
			xx = 0
			yy = y+1
		else
			xx = x + odd
			yy = y + 1
		end
		return xx,yy
	elseif dir == mc.E then
		if x == self.width-1 and self.wrapX then
			xx = 0
			yy = y
		else
			xx = x + 1
			yy = y
		end
		return xx,yy
	elseif dir == mc.SE then
		if x == self.width-1 and odd == 1 and self.wrapX then
			xx = 0
			yy = y - 1
		else
			xx = x + odd
			yy = y - 1
		end
		return xx,yy
	elseif dir == mc.SW then
		if x == 0 and odd == 0 and self.wrapX then
			xx = self.width - 1
			yy = y - 1
		else
			xx = x - 1 + odd
			yy = y - 1
		end
		return xx,yy
	else
		error("Bad direction in FloatMap:GetNeighbor")
	end
	return -1,-1
end
-------------------------------------------------------------------------------------------
function FloatMap:GetIndex(x,y)
	local xx
	if self.wrapX then
		xx = x % self.width
	elseif x < 0 or x > self.width - 1 then
		return -1
	else
		xx = x
	end

	if self.wrapY then
		yy = y % self.height
	elseif y < 0 or y > self.height - 1 then
		return -1
	else
		yy = y
	end

	return yy * self.width + xx
end
-------------------------------------------------------------------------------------------
function FloatMap:GetXYFromIndex(i)
	local x = i % self.width
	local y = (i - x)/self.width
	return x,y
end
-------------------------------------------------------------------------------------------
--quadrants are labeled
--A B
--D C
function FloatMap:GetQuadrant(x,y)
	if x < self.width/2 then
		if y < self.height/2 then
			return "A"
		else
			return "D"
		end
	else
		if y < self.height/2 then
			return "B"
		else
			return "C"
		end
	end
end
-------------------------------------------------------------------------------------------
--Gets an index for x and y based on the current
--rect settings. x and y are local to the defined rect.
--Wrapping is assumed in both directions
function FloatMap:GetRectIndex(x,y)
	local xx = x % self.rectWidth
	local yy = y % self.rectHeight

	xx = self.rectX + xx
	yy = self.rectY + yy

	return self:GetIndex(xx,yy)
end
-------------------------------------------------------------------------------------------
function FloatMap:Normalize()
	--find highest and lowest values
	local maxAlt = -1000.0
	local minAlt = 1000.0
	for i = 0,self.length - 1,1 do
		local alt = self.data[i]
		if alt > maxAlt then
			maxAlt = alt
		elseif alt < minAlt then
			minAlt = alt
		end
	end
	--subtract minAlt from all values so that
	--all values are zero and above
	for i = 0, self.length - 1, 1 do
		self.data[i] = self.data[i] - minAlt
	end

	--subract minAlt also from maxAlt
	maxAlt = maxAlt - minAlt

	--determine and apply scaler to whole map
	local scaler
	if maxAlt == 0.0 then
		scaler = 0.0
	else
		scaler = 1.0/maxAlt
	end

	for i = 0,self.length - 1,1 do
		self.data[i] = self.data[i] * scaler
	end

end
-------------------------------------------------------------------------------------------
function FloatMap:GenerateNoise()
	for i = 0,self.length - 1,1 do
		self.data[i] = PWRand()
	end

end
-------------------------------------------------------------------------------------------
function FloatMap:GenerateBinaryNoise()
	for i = 0,self.length - 1,1 do
		if PWRand() > 0.5 then
			self.data[i] = 1
		else
			self.data[i] = 0
		end
	end

end
-------------------------------------------------------------------------------------------
function FloatMap:FindThresholdFromPercent(percent, greaterThan, excludeZeros)
	local mapList = {}
	local percentage = percent * 100
	local const = 0.0
	
	if not excludeZeros then
		const = 0.000000000000000001
	end
	
	if greaterThan then
		percentage = 100-percentage
	end

	if percentage >= 100 then
		return 1.01 --whole map
	elseif percentage <= 0 then
		return -0.01 --none of the map
	end
	
	for i=0,self.length-1,1 do
		if not (self.data[i] == 0.0 and excludeZeros) then
			table.insert(mapList,self.data[i])
		end
	end
	
	table.sort(mapList, function (a,b) return a < b end)
	local threshIndex = math.floor((#mapList * percentage)/100) 

	return mapList[threshIndex-1]+const
end
-------------------------------------------------------------------------------------------
function FloatMap:GetLatitudeForY(y)
	local range = mc.topLatitude - mc.bottomLatitude
	local lat = nil
	if y < self.height/2 then
		lat = (y+1) / self.height * range + (mc.bottomLatitude - mc.topLatitude / self.height)
	else
		lat = y / self.height * range + (mc.bottomLatitude + mc.topLatitude / self.height)
	end
	return lat
end
-------------------------------------------------------------------------------------------
function FloatMap:GetYForLatitude(lat)
	local range = mc.topLatitude - mc.bottomLatitude
	local y = nil
	if lat < 0 then
		y = math.floor(((lat - (mc.bottomLatitude - mc.topLatitude / self.height)) / range * self.height))
	else
		y = math.ceil(((lat - (mc.bottomLatitude + mc.topLatitude / self.height)) / range * self.height) - 1)
	end
	return y
end
-------------------------------------------------------------------------------------------
function FloatMap:GetZone(y)
	local lat = self:GetLatitudeForY(y)
	if y < 0 or y >= self.height then
		return mc.NOZONE
	end
	if lat > mc.polarFrontLatitude then
		return mc.NPOLAR
	elseif lat >= mc.horseLatitudes then
		return mc.NTEMPERATE
	elseif lat >= 0.0 then
		return mc.NEQUATOR
	elseif lat > -mc.horseLatitudes then
		return mc.SEQUATOR
	elseif lat >= -mc.polarFrontLatitude then
		return mc.STEMPERATE
	else
		return mc.SPOLAR
	end
end
-------------------------------------------------------------------------------------------
function FloatMap:GetYFromZone(zone, bTop)
	if bTop then
		for y=self.height - 1,0,-1 do
			if zone == self:GetZone(y) then
				return y
			end
		end
	else
		for y=0,self.height - 1,1 do
			if zone == self:GetZone(y) then
				return y
			end
		end
	end
	return -1
end
-------------------------------------------------------------------------------------------
function FloatMap:GetGeostrophicWindDirections(zone)

	if zone == mc.NPOLAR then
		return mc.SW,mc.W
	elseif zone == mc.NTEMPERATE then
		return mc.NE,mc.E
	elseif zone == mc.NEQUATOR then
		return mc.SW,mc.W
	elseif zone == mc.SEQUATOR then
		return mc.NW,mc.W
	elseif zone == mc.STEMPERATE then
		return mc.SE, mc.E
	else
		return mc.NW,mc.W
	end
	return -1,-1
end
-------------------------------------------------------------------------------------------
function FloatMap:GetGeostrophicPressure(lat)
	local latRange = nil
	local latPercent = nil
	local pressure = nil
	if lat > mc.polarFrontLatitude then
		latRange = 90.0 - mc.polarFrontLatitude
		latPercent = (lat - mc.polarFrontLatitude)/latRange
		pressure = 1.0 - latPercent
	elseif lat >= mc.horseLatitudes then
		latRange = mc.polarFrontLatitude - mc.horseLatitudes
		latPercent = (lat - mc.horseLatitudes)/latRange
		pressure = latPercent
	elseif lat >= 0.0 then
		latRange = mc.horseLatitudes - 0.0
		latPercent = (lat - 0.0)/latRange
		pressure = 1.0 - latPercent
	elseif lat > -mc.horseLatitudes then
		latRange = 0.0 + mc.horseLatitudes
		latPercent = (lat + mc.horseLatitudes)/latRange
		pressure = latPercent
	elseif lat >= -mc.polarFrontLatitude then
		latRange = -mc.horseLatitudes + mc.polarFrontLatitude
		latPercent = (lat + mc.polarFrontLatitude)/latRange
		pressure = 1.0 - latPercent
	else
		latRange = -mc.polarFrontLatitude + 90.0
		latPercent = (lat + 90)/latRange
		pressure = latPercent
	end
	pressure = pressure + 1
	if pressure > 1.5 then
		pressure = pressure * mc.pressureNorm
	else
		pressure = pressure / mc.pressureNorm
	end
	pressure = pressure - 1
	--print(pressure)
	return pressure
end
-------------------------------------------------------------------------------------------
function FloatMap:ApplyFunction(func)
	for i = 0,self.length - 1,1 do
		self.data[i] = func(self.data[i])
	end
end
-------------------------------------------------------------------------------------------
function GetCircle(i,radius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local tab = {}
	local topY = radius
	local bottomY = radius
	local currentY = nil
	local len = 1+radius
	
	--constrain the top of our circle to be on the map
	if y+radius > H-1 then
		for r=0,radius-1,1 do
			if y+r == H-1 then
				topY = r
				break
			end
		end
	end
	--constrain the bottom of our circle to be on the map
	if y-radius < 0 then
		for r=0,radius,1 do
			if y-r == 0 then
				bottomY = r
				break
			end
		end
	end
	
	--adjust starting length, apply the top and bottom limits, and correct odd for the starting point
	len = len+(radius-bottomY)
	currentY = y - bottomY
	topY = y + topY
	odd = (odd+bottomY)%2
	--set the starting point, the if statement checks for xWrap
	if x-(radius-bottomY)-math.floor((bottomY+odd)/2) < 0 then
		i = i-(W*bottomY)+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		x = x+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
	else
		i = i-(W*bottomY)-(radius-bottomY)-math.floor((bottomY+odd)/2)
		x = x-(radius-bottomY)-math.floor((bottomY+odd)/2)
	end
	
	--cycle through the plot indexes and add them to a table
	while currentY <= topY do
		--insert the start value, scan left to right adding each index in the line to our table
		table.insert(tab,i)
		
		local wrapped = false
		for n=1,len-1,1 do
			if x ~= (W-1) then
				i = i + 1
				x = x + 1
			else
				i = i-(W-1)
				x = 0
				wrapped = true
			end
			table.insert(tab,i)
		end
		
		if currentY < y then
			--move i NW and increment the length to scan
			if not wrapped then
				i = i+W-len+odd
				x = x-len+odd
			else
				i = i+W+(W-len+odd)
				x = x+(W-len+odd)
			end
			len = len+1
		else
			--move i NE and decrement the length to scan
			if not wrapped then
				i = i+W-len+1+odd
				x = x-len+1+odd
			else
				i = i+W+(W-len+1+odd)
				x = x+(W-len+1+odd)
			end
			len = len-1
		end
		
		currentY = currentY+1
		if odd == 0 then
			odd = 1
		else
			odd = 0
		end
	end
	return tab
end
-------------------------------------------------------------------------------------------
function GetSpiral(i,maxRadius,minRadius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local tab ={}
	local first = true

	
	if minRadius == nil or minRadius == 0 then
		table.insert(tab,i)
		minRadius = 1
	end
	
	for r = minRadius, maxRadius, 1 do
		if first == true then
			--start r to the west on the first spiral
			if x-r > -1 then
				i = i-r
				x = x-r
			else
				i = i+(W-r)
				x = x+(W-r)
			end
			first = false
		else
			--go west 1 tile before the next spiral
			if x ~= 0 then
				i = i-1
				x = x-1
			else
				i = i+(W-1)
				x = W-1
			end
		end
		--Go r times to the NE
		for z=1,r,1 do
			if x ~= (W-1) or odd == 0 then
				i = i+W+odd
				x = x+odd
			else
				i = i + 1
				x = 0
			end
			
			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
		--Go r times to the E
		for z=1,r,1 do
			if x ~= (W-1) then
				i = i+1
				x = x+1
			else
				i = i-(W-1)
				x = 0
			end
						
			--store the index value or -1 if the plot isn't on the map
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
		end
		--Go r times to the SE
		for z=1,r,1 do
			if x ~= (W-1) or odd == 0 then
				i = i-W+odd
				x = x+odd
			else
				i = i-(W+(W-1))
				x = 0
			end
						
			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
		--Go r times to the SW
		for z=1,r,1 do
			if x ~= 0 or odd == 1 then
				i = i-W-1+odd
				x = x-1+odd
			else
				i = i-(W+1)
				x = (W-1)
			end
						
			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
		--Go r times to the W
		for z = 1,r,1 do
			if x ~= 0 then
				i = i-1
				x=x-1
			else
				i = i+(W-1)
				x = (W-1)
			end
						
			--store the index value or -1 if the plot isn't on the map
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
		end
		--Go r times to the NW!!!!!
		for z = 1,r,1 do
			if x ~= 0 or odd == 1 then
				i = i+W-1+odd
				x = x-1+odd
			else
				i = i+W+(W-1)
				x = W-1
			end
						
			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
	end

	return tab
end
-------------------------------------------------------------------------------------------
function FloatMap:GetAverageInHex(i,radius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local topY = radius
	local bottomY = radius
	local currentY = nil
	local len = 1+radius
	local avg = 0
	local count = 0
	
	--constrain the top of our circle to be on the map
	if y+radius > H-1 then
		for r=0,radius-1,1 do
			if y+r == H-1 then
				topY = r
				break
			end
		end
	end
	--constrain the bottom of our circle to be on the map
	if y-radius < 0 then
		for r=0,radius,1 do
			if y-r == 0 then
				bottomY = r
				break
			end
		end
	end
	
	--adjust starting length, apply the top and bottom limits, and correct odd for the starting point
	len = len+(radius-bottomY)
	currentY = y - bottomY
	topY = y + topY
	odd = (odd+bottomY)%2
	--set the starting point, the if statement checks for xWrap
	if x-(radius-bottomY)-math.floor((bottomY+odd)/2) < 0 then
		i = i-(W*bottomY)+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		x = x+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		-- print(string.format("i for (%d,%d) WOULD have been in outer space. x is (%d,%d) i is (%d)",xx,y,x,y-bottomY,i))
	else
		i = i-(W*bottomY)-(radius-bottomY)-math.floor((bottomY+odd)/2)
		x = x-(radius-bottomY)-math.floor((bottomY+odd)/2)
	end
	
	--cycle through the plot indexes and add them to a table
	while currentY <= topY do
		--insert the start value, scan left to right adding each index in the line to our table
		
		avg = avg+self.data[i]
		local wrapped = false
		for n=1,len-1,1 do
			if x ~= (W-1) then
				i = i + 1
				x = x + 1
			else
				i = i-(W-1)
				x = 0
				wrapped = true
			end
			avg = avg+self.data[i]
			count = count+1
		end
		
		if currentY < y then
			--move i NW and increment the length to scan
			if not wrapped then
				i = i+W-len+odd
				x = x-len+odd
			else
				i = i+W+(W-len+odd)
				x = x+(W-len+odd)
			end
			len = len+1
		else
			--move i NE and decrement the length to scan
			if not wrapped then
				i = i+W-len+1+odd
				x = x-len+1+odd
			else
				i = i+W+(W-len+1+odd)
				x = x+(W-len+1+odd)
			end
			len = len-1
		end
		
		currentY = currentY+1
		if odd == 0 then
			odd = 1
		else
			odd = 0
		end
	end

	avg = avg/count
	return avg
end
-------------------------------------------------------------------------------------------
function FloatMap:GetStdDevInHex(i,radius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local topY = radius
	local bottomY = radius
	local currentY = nil
	local len = 1+radius
	local avg = self:GetAverageInHex(i,radius)
	local deviation = 0
	local count = 0
	
	--constrain the top of our circle to be on the map
	if y+radius > H-1 then
		for r=0,radius-1,1 do
			if y+r == H-1 then
				topY = r
				break
			end
		end
	end
	--constrain the bottom of our circle to be on the map
	if y-radius < 0 then
		for r=0,radius,1 do
			if y-r == 0 then
				bottomY = r
				break
			end
		end
	end
	
	--adjust starting length, apply the top and bottom limits, and correct odd for the starting point
	len = len+(radius-bottomY)
	currentY = y - bottomY
	topY = y + topY
	odd = (odd+bottomY)%2
	--set the starting point, the if statement checks for xWrap
	if x-(radius-bottomY)-math.floor((bottomY+odd)/2) < 0 then
		i = i-(W*bottomY)+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		x = x+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
	else
		i = i-(W*bottomY)-(radius-bottomY)-math.floor((bottomY+odd)/2)
		x = x-(radius-bottomY)-math.floor((bottomY+odd)/2)
	end
	
	--cycle through the plot indexes and add them to a table
	while currentY <= topY do
		--insert the start value, scan left to right adding each index in the line to our table
		
		local sqr = self.data[i] - avg
		deviation = deviation + (sqr * sqr)
		local wrapped = false
		for n=1,len-1,1 do
			if x ~= (W-1) then
				i = i + 1
				x = x + 1
			else
				i = i-(W-1)
				x = 0
				wrapped = true
			end
			
			sqr = self.data[i] - avg
			deviation = deviation + (sqr * sqr)
			count = count+1
		end
		
		if currentY < y then
			--move i NW and increment the length to scan
			if not wrapped then
				i = i+W-len+odd
				x = x-len+odd
			else
				i = i+W+(W-len+odd)
				x = x+(W-len+odd)
			end
			len = len+1
		else
			--move i NE and decrement the length to scan
			if not wrapped then
				i = i+W-len+1+odd
				x = x-len+1+odd
			else
				i = i+W+(W-len+1+odd)
				x = x+(W-len+1+odd)
			end
			len = len-1
		end
		
		currentY = currentY+1
		if odd == 0 then
			odd = 1
		else
			odd = 0
		end
	end

	deviation = math.sqrt(deviation/count)
	return deviation
end
-------------------------------------------------------------------------------------------
function FloatMap:Smooth(radius)
	local dataCopy = {}
	
	if radius > 8 then
		radius = 8
	end
	
	for i=0,self.length-1,1 do
		dataCopy[i] = self:GetAverageInHex(i,radius)
	end
	
	self.data = dataCopy
end
-------------------------------------------------------------------------------------------
function FloatMap:Deviate(radius)
	local dataCopy = {}

	if radius > 7 then
		radius = 7
	end
	for i=0,self.length-1,1 do
		dataCopy[i] = self:GetStdDevInHex(i,radius)
	end
	
	self.data = dataCopy
end
-------------------------------------------------------------------------------------------
function FloatMap:IsOnMap(x,y)
	local i = self:GetIndex(x,y)
	if i == -1 then
		return false
	end
	return true
end
-------------------------------------------------------------------------------------------
function FloatMap:Save(name)
	print("saving " .. name .. "...")
	local str = self.width .. "," .. self.height
	for i = 0,self.length - 1,1 do
		str = str .. "," .. self.data[i]
	end
	local file = io.open(name,"w+")
	file:write(str)
	file:close()
	print("bitmap saved as " .. name .. ".")
end
-------------------------------------------------------------------------------------------
function FloatMap:Save4(name)
	local file = io.open(name,"w+")
	local first = true
	local str = ""
	for y = self.height, 0, -1 do
		if first then
			str = "xy,"
		else
			str = string.format("%d,",y)
		end
		for x = 0, self.width-1 do
			local i = y*self.width+(x%self.width)
			if first then
				if x < self.width-1 then
					str = str..string.format("%d,",x)
				else
					str = str..string.format("%d\n",x)
				end
			elseif x < self.width-1 then
				str = str..string.format("%.12f,",self.data[i])
			else
				str = str..string.format("%.12f\n",self.data[i])
			end
		end
		first = false
		file:write(str)
	end
	file:close()
	print("bitmap saved as "..name..".")
end
-------------------------------------------------------------------------------------------
--ElevationMap class
-------------------------------------------------------------------------------------------
ElevationMap = inheritsFrom(FloatMap)

function ElevationMap:New(width, height, wrapX, wrapY)
	local new_inst = FloatMap:New(width,height,wrapX,wrapY)
	setmetatable(new_inst, {__index = ElevationMap});	--setup metatable
	return new_inst
end
-------------------------------------------------------------------------------------------
function ElevationMap:IsBelowSeaLevel(x,y)
	local i = self:GetIndex(x,y)
	if self.data[i] < self.seaLevelThreshold then
		return true
	else
		return false
	end
end
-------------------------------------------------------------------------------------------
--AreaMap class
-------------------------------------------------------------------------------------------
PWAreaMap = inheritsFrom(FloatMap)

function PWAreaMap:New(width,height,wrapX,wrapY)
	local new_inst = FloatMap:New(width,height,wrapX,wrapY)
	setmetatable(new_inst, {__index = PWAreaMap});	--setup metatable

	new_inst.areaList = {}
	new_inst.segStack = {}
	return new_inst
end
-------------------------------------------------------------------------------------------
function PWAreaMap:DefineAreas(matchFunction)
	--zero map data
	for i = 0,self.width*self.height - 1,1 do
		self.data[i] = 0.0
	end

	self.areaList = {}
	local currentAreaID = 0
	local i = 0
	for y = 0, self.height - 1,1 do
		for x = 0, self.width - 1,1 do
			if self.data[i] == 0 then
				currentAreaID = currentAreaID + 1
				local area = PWArea:New(currentAreaID,x,y,matchFunction(x,y))
				--print(string.format("Filling area %d, matchFunction(x = %d,y = %d) = %s",area.id,x,y,tostring(matchFunction(x,y)))
				self:FillArea(x,y,area,matchFunction)
				table.insert(self.areaList, area)
			end
			i=i+1
		end
	end
end
-------------------------------------------------------------------------------------------
function PWAreaMap:FillArea(x,y,area,matchFunction)
	self.segStack = {}
	local seg = LineSeg:New(y,x,x,1)
	Push(self.segStack,seg)
	seg = LineSeg:New(y + 1,x,x,-1)
	Push(self.segStack,seg)
	while #self.segStack > 0 do
		seg = Pop(self.segStack)
		self:ScanAndFillLine(seg,area,matchFunction)
	end
end
-------------------------------------------------------------------------------------------
function PWAreaMap:ScanAndFillLine(seg,area,matchFunction)

	--str = string.format("Processing line y = %d, xLeft = %d, xRight = %d, dy = %d -------",seg.y,seg.xLeft,seg.xRight,seg.dy)
	--print(str)
	if self:ValidateY(seg.y + seg.dy) == -1 then
		return
	end

	local odd = (seg.y + seg.dy) % 2
	local notOdd = seg.y % 2
	--str = string.format("odd = %d, notOdd = %d",odd,notOdd)
	--print(str)

	local lineFound = 0
	local xStop = nil
	if self.wrapX then
		xStop = 0 - (self.width * 30)
	else
		xStop = -1
	end
	local leftExtreme = nil
	for leftExt = seg.xLeft - odd,xStop + 1,-1 do
		leftExtreme = leftExt --need this saved
		--str = string.format("leftExtreme = %d",leftExtreme)
		--print(str)
		local x = self:ValidateX(leftExtreme)
		local y = self:ValidateY(seg.y + seg.dy)
		local i = self:GetIndex(x,y)
		--str = string.format("x = %d, y = %d, area.trueMatch = %s, matchFunction(x,y) = %s",x,y,tostring(area.trueMatch),tostring(matchFunction(x,y)))
		--print(str)
		if self.data[i] == 0 and area.trueMatch == matchFunction(x,y) then
			self.data[i] = area.id
			area.size = area.size + 1
			--print("adding to area")
			lineFound = 1
		else
			--if no line was found, then leftExtreme is fine, but if
			--a line was found going left, then we need to increment
            --xLeftExtreme to represent the inclusive end of the line
			if lineFound == 1 then
				leftExtreme = leftExtreme + 1
				--print("line found, adding 1 to leftExtreme")
			end
			break
		end
	end
	--str = string.format("leftExtreme = %d",leftExtreme)
	--print(str)
	local rightExtreme = nil
	--now scan right to find extreme right, place each found segment on stack
	if self.wrapX then
		xStop = self.width * 20
	else
		xStop = self.width
	end
	for rightExt = seg.xLeft + lineFound - odd,xStop - 1,1 do
		rightExtreme = rightExt --need this saved
		--str = string.format("rightExtreme = %d",rightExtreme)
		--print(str)
		local x = self:ValidateX(rightExtreme)
		local y = self:ValidateY(seg.y + seg.dy)
		local i = self:GetIndex(x,y)
		--str = string.format("x = %d, y = %d, area.trueMatch = %s, matchFunction(x,y) = %s",x,y,tostring(area.trueMatch),tostring(matchFunction(x,y)))
		--print(str)
		if self.data[i] == 0 and area.trueMatch == matchFunction(x,y) then
			self.data[i] = area.id
			area.size = area.size + 1
			--print("adding to area")
			if lineFound == 0 then
				lineFound = 1 --starting new line
				leftExtreme = rightExtreme
			end
		elseif lineFound == 1 then --found the right end of a line segment
			--print("found right end of line")
			lineFound = 0
			--put same direction on stack
			local newSeg = LineSeg:New(y,leftExtreme,rightExtreme - 1,seg.dy)
			Push(self.segStack,newSeg)
			--str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",y,leftExtreme,rightExtreme - 1,seg.dy)
			--print(str)
			--determine if we must put reverse direction on stack
			if leftExtreme < seg.xLeft - odd or rightExtreme >= seg.xRight + notOdd then
				--out of shadow so put reverse direction on stack
				newSeg = LineSeg:New(y,leftExtreme,rightExtreme - 1,-seg.dy)
				Push(self.segStack,newSeg)
				--str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",y,leftExtreme,rightExtreme - 1,-seg.dy)
				--print(str)
			end
			if(rightExtreme >= seg.xRight + notOdd) then
				break
			end
		elseif lineFound == 0 and rightExtreme >= seg.xRight + notOdd then
			break --past the end of the parent line and no line found
		end
		--continue finding segments
	end
	if lineFound == 1 then --still needing a line to be put on stack
		print("still need line segments")
		lineFound = 0
		--put same direction on stack
		local newSeg = LineSeg:New(seg.y + seg.dy,leftExtreme,rightExtreme - 1,seg.dy)
		Push(self.segStack,newSeg)
		str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",seg.y + seg.dy,leftExtreme,rightExtreme - 1,seg.dy)
		print(str)
		--determine if we must put reverse direction on stack
		if leftExtreme < seg.xLeft - odd or rightExtreme >= seg.xRight + notOdd then
			--out of shadow so put reverse direction on stack
			newSeg = LineSeg:New(seg.y + seg.dy,leftExtreme,rightExtreme - 1,-seg.dy)
			Push(self.segStack,newSeg)
			str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",seg.y + seg.dy,leftExtreme,rightExtreme - 1,-seg.dy)
			print(str)
		end
	end
end
-------------------------------------------------------------------------------------------
function PWAreaMap:GetAreaByID(id)
	for i = 1,#self.areaList,1 do
		if self.areaList[i].id == id then
			return self.areaList[i]
		end
	end
	error("Can't find area id in AreaMap.areaList")
end
-------------------------------------------------------------------------------------------
function PWAreaMap:ValidateY(y)
	local yy = nil
	if self.wrapY then
		yy = y % self.height
	elseif y < 0 or y >= self.height then
		return -1
	else
		yy = y
	end
	return yy
end
-------------------------------------------------------------------------------------------
function PWAreaMap:ValidateX(x)
	local xx = nil
	if self.wrapX then
		xx = x % self.width
	elseif x < 0 or x >= self.width then
		return -1
	else
		xx = x
	end
	return xx
end
-------------------------------------------------------------------------------------------
function PWAreaMap:PrintAreaList()
	for i=1,#self.areaList,1 do
		local id = self.areaList[i].id
		local seedx = self.areaList[i].seedx
		local seedy = self.areaList[i].seedy
		local size = self.areaList[i].size
		local trueMatch = self.areaList[i].trueMatch
		local str = string.format("area id = %d, trueMatch = %s, size = %d, seedx = %d, seedy = %d",id,tostring(trueMatch),size,seedx,seedy)
		print(str)
	end
end
-------------------------------------------------------------------------------------------
--Area class
-------------------------------------------------------------------------------------------
PWArea = inheritsFrom(nil)

function PWArea:New(id,seedx,seedy,trueMatch)
	local new_inst = {}
	setmetatable(new_inst, {__index = PWArea});	--setup metatable

	new_inst.id = id
	new_inst.seedx = seedx
	new_inst.seedy = seedy
	new_inst.trueMatch = trueMatch
	new_inst.size = 0

	return new_inst
end
-------------------------------------------------------------------------------------------
--LineSeg class
-------------------------------------------------------------------------------------------
LineSeg = inheritsFrom(nil)

function LineSeg:New(y,xLeft,xRight,dy)
	local new_inst = {}
	setmetatable(new_inst, {__index = LineSeg});	--setup metatable

	new_inst.y = y
	new_inst.xLeft = xLeft
	new_inst.xRight = xRight
	new_inst.dy = dy

	return new_inst
end
-------------------------------------------------------------------------------------------
--RiverMap class
-------------------------------------------------------------------------------------------
RiverMap = inheritsFrom(nil)

function RiverMap:New()
	local new_inst = {}
	setmetatable(new_inst, {__index = RiverMap});

	--new_inst.g_ElevationMap = g_ElevationMap
	new_inst.riverData = {}
	local i = 0
	for y = 0,g_ElevationMap.height - 1,1 do
		for x = 0,g_ElevationMap.width - 1,1 do
			new_inst.riverData[i] = RiverHex:New(x,y)
			i=i+1
		end
	end

	return new_inst
end
-------------------------------------------------------------------------------------------
function RiverMap:GetJunction(x,y,isNorth)
	local i = g_ElevationMap:GetIndex(x,y)
	if isNorth then
		return self.riverData[i].northJunction
	else
		return self.riverData[i].southJunction
	end
end
-------------------------------------------------------------------------------------------
function RiverMap:GetJunctionNeighbor(direction,junction)
	local xx = nil
	local yy = nil
	local ii = nil
	local neighbor = nil
	local odd = junction.y % 2
	if direction == mc.NOFLOW then
		error("can't get junction neighbor in direction NOFLOW")
	elseif direction == mc.WESTFLOW then
		xx = junction.x + odd - 1
		if junction.isNorth then
			yy = junction.y + 1
		else
			yy = junction.y - 1
		end
		ii = g_ElevationMap:GetIndex(xx,yy)
		if ii ~= -1 then
			neighbor = self:GetJunction(xx,yy,not junction.isNorth)
			return neighbor
		end
	elseif direction == mc.EASTFLOW then
		xx = junction.x + odd
		if junction.isNorth then
			yy = junction.y + 1
		else
			yy = junction.y - 1
		end
		ii = g_ElevationMap:GetIndex(xx,yy)
		if ii ~= -1 then
			neighbor = self:GetJunction(xx,yy,not junction.isNorth)
			return neighbor
		end
	elseif direction == mc.VERTFLOW then
		xx = junction.x
		if junction.isNorth then
			yy = junction.y + 2
		else
			yy = junction.y - 2
		end
		ii = g_ElevationMap:GetIndex(xx,yy)
		if ii ~= -1 then
			neighbor = self:GetJunction(xx,yy,not junction.isNorth)
			return neighbor
		end
	end

	return nil --neighbor off map
end
-------------------------------------------------------------------------------------------
--Get the west or east hex neighboring this junction
function RiverMap:GetRiverHexNeighbor(junction,westNeighbor)
	local xx = nil
	local yy = nil
	local ii = nil
	local odd = junction.y % 2
	if junction.isNorth then
		yy = junction.y + 1
	else
		yy = junction.y - 1
	end
	if westNeighbor then
		xx = junction.x + odd - 1
	else
		xx = junction.x + odd
	end

	ii = g_ElevationMap:GetIndex(xx,yy)
	if ii ~= -1 then
		return self.riverData[ii]
	end

	return nil
end
-------------------------------------------------------------------------------------------
function RiverMap:SetJunctionAltitudes()
	local i = 0
	for y = 0,g_ElevationMap.height - 1,1 do
		for x = 0,g_ElevationMap.width - 1,1 do
			local vertAltitude = g_ElevationMap.data[i]
			local westAltitude = nil
			local eastAltitude = nil
			local vertNeighbor = self.riverData[i]
			local westNeighbor = nil
			local eastNeighbor = nil

			--first do north
			westNeighbor = self:GetRiverHexNeighbor(vertNeighbor.northJunction,true)
			eastNeighbor = self:GetRiverHexNeighbor(vertNeighbor.northJunction,false)

			if westNeighbor ~= nil then
				westAltitude = g_ElevationMap.data[g_ElevationMap:GetIndex(westNeighbor.x,westNeighbor.y)]
			else
				westAltitude = vertAltitude
			end

			if eastNeighbor ~= nil then
				eastAltitude = g_ElevationMap.data[g_ElevationMap:GetIndex(eastNeighbor.x, eastNeighbor.y)]
			else
				eastAltitude = vertAltitude
			end

			vertNeighbor.northJunction.altitude = math.min(math.min(vertAltitude,westAltitude),eastAltitude)

			--then south
			westNeighbor = self:GetRiverHexNeighbor(vertNeighbor.southJunction,true)
			eastNeighbor = self:GetRiverHexNeighbor(vertNeighbor.southJunction,false)

			if westNeighbor ~= nil then
				westAltitude = g_ElevationMap.data[g_ElevationMap:GetIndex(westNeighbor.x,westNeighbor.y)]
			else
				westAltitude = vertAltitude
			end

			if eastNeighbor ~= nil then
				eastAltitude = g_ElevationMap.data[g_ElevationMap:GetIndex(eastNeighbor.x, eastNeighbor.y)]
			else
				eastAltitude = vertAltitude
			end

			vertNeighbor.southJunction.altitude = math.min(math.min(vertAltitude,westAltitude),eastAltitude)
			i=i+1
		end
	end
end
-------------------------------------------------------------------------------------------
function RiverMap:isLake(junction)

	--first exclude the map edges that don't have neighbors
	if junction.y == 0 and junction.isNorth == false then
		return false
	elseif junction.y == g_ElevationMap.height - 1 and junction.isNorth == true then
		return false
	end

	--exclude altitudes below sea level
	if junction.altitude < g_ElevationMap.seaLevelThreshold then
		return false
	end

	--print(string.format("junction = (%d,%d) N = %s, alt = %f",junction.x,junction.y,tostring(junction.isNorth),junction.altitude))

	local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
	local vertAltitude = nil
	if vertNeighbor == nil then
		vertAltitude = junction.altitude
		--print("--vertNeighbor == nil")
	else
		vertAltitude = vertNeighbor.altitude
		--print(string.format("--vertNeighbor = (%d,%d) N = %s, alt = %f",vertNeighbor.x,vertNeighbor.y,tostring(vertNeighbor.isNorth),vertNeighbor.altitude))
	end

	local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
	local westAltitude = nil
	if westNeighbor == nil then
		westAltitude = junction.altitude
		--print("--westNeighbor == nil")
	else
		westAltitude = westNeighbor.altitude
		--print(string.format("--westNeighbor = (%d,%d) N = %s, alt = %f",westNeighbor.x,westNeighbor.y,tostring(westNeighbor.isNorth),westNeighbor.altitude))
	end

	local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
	local eastAltitude = nil
	if eastNeighbor == nil then
		eastAltitude = junction.altitude
		--print("--eastNeighbor == nil")
	else
		eastAltitude = eastNeighbor.altitude
		--print(string.format("--eastNeighbor = (%d,%d) N = %s, alt = %f",eastNeighbor.x,eastNeighbor.y,tostring(eastNeighbor.isNorth),eastNeighbor.altitude))
	end

	local lowest = math.min(vertAltitude,math.min(westAltitude,math.min(eastAltitude,junction.altitude)))

	if lowest == junction.altitude then
		--print("--is lake")
		return true
	end
	--print("--is not lake")
	return false
end
-------------------------------------------------------------------------------------------
--get the average altitude of the two lowest neighbors that are higher than
--the junction altitude.
function RiverMap:GetNeighborAverage(junction)
	local count = 0
	local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
	local vertAltitude = nil
	if vertNeighbor == nil then
		vertAltitude = 0
	else
		vertAltitude = vertNeighbor.altitude
		count = count +1
	end

	local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
	local westAltitude = nil
	if westNeighbor == nil then
		westAltitude = 0
	else
		westAltitude = westNeighbor.altitude
		count = count +1
	end

	local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
	local eastAltitude = nil
	if eastNeighbor == nil then
		eastAltitude = 0
	else
		eastAltitude = eastNeighbor.altitude
		count = count +1
	end

	local avg = (vertAltitude + westAltitude + eastAltitude)/count
	return avg
end
-------------------------------------------------------------------------------------------
--this function alters the drainage pattern
function RiverMap:SiltifyLakes()
	local Time3 = os.clock()
	local lakeList = {}
	local onQueueMapNorth = {}
	local onQueueMapSouth = {}
	
	for i=0,g_ElevationMap.length-1,1 do
		if self:isLake(self.riverData[i].northJunction) then
			table.insert(lakeList,self.riverData[i].northJunction)
			onQueueMapNorth[i] = true
		else
			onQueueMapNorth[i] = false
		end
		if self:isLake(self.riverData[i].southJunction) then
			table.insert(lakeList,self.riverData[i].southJunction)
			onQueueMapSouth[i] = true
		else
			onQueueMapSouth[i] = false
		end
	end

	
	local iterations = 0
	--print(string.format("Initial lake count = %d",#lakeList))
	while #lakeList > 0 do
		iterations = iterations + 1
		if iterations > 100000000 then
			--debugOn = true
			print("###ERROR### - Endless loop in lake siltification.")
			break
		end

		local junction = table.remove(lakeList)
		local i = g_ElevationMap:GetIndex(junction.x,junction.y)
		if junction.isNorth then
			onQueueMapNorth[i] = false
		else
			onQueueMapSouth[i] = false
		end
		
		local avg = self:GetNeighborAverage(junction)
		if avg < junction.altitude + 0.0001 then --using == in fp comparison is precarious and unpredictable due to sp vs. dp floats, rounding, and all that nonsense. =P
			while self:isLake(junction) do
				junction.altitude = junction.altitude + 0.0001
			end
		else
			junction.altitude = avg
		end

		for dir = mc.WESTFLOW,mc.VERTFLOW,1 do
			local neighbor = self:GetJunctionNeighbor(dir,junction)
			if neighbor ~= nil and self:isLake(neighbor) then
				local ii = g_ElevationMap:GetIndex(neighbor.x,neighbor.y)
				if neighbor.isNorth == true and onQueueMapNorth[ii] == false then
					table.insert(lakeList,neighbor)
					onQueueMapNorth[ii] = true
				elseif neighbor.isNorth == false and onQueueMapSouth[ii] == false then
					table.insert(lakeList,neighbor)
					onQueueMapSouth[ii] = true
				end
			end
		end
	end
	print(string.format("Siltified Lakes in %.4f seconds over %d iterations. - PerfectWorld3",os.clock()-Time3,iterations))

--[[Commented out this section because it's debug code that forces a crash. -Bobert13
	local belowSeaLevelCount = 0
	local riverTest = FloatMap:New(g_ElevationMap.width,g_ElevationMap.height,g_ElevationMap.xWrap,g_ElevationMap.yWrap)
	local lakesFound = false
	for i=0, g_ElevationMap.length-1,1 do
		local northAltitude = self.riverData[i].northJunction.altitude
		local southAltitude = self.riverData[i].southJunction.altitude
		if northAltitude < g_ElevationMap.seaLevelThreshold then
			belowSeaLevelCount = belowSeaLevelCount + 1
		end
		if southAltitude < g_ElevationMap.seaLevelThreshold then
			belowSeaLevelCount = belowSeaLevelCount + 1
		end
		riverTest.data[i] = (northAltitude + southAltitude)/2.0

		if self:isLake(self.riverData[i].northJunction) then
			local junction = self.riverData[i].northJunction
			print(string.format("lake found at (%d, %d) isNorth = %s, altitude = %.12f!",junction.x,junction.y,tostring(junction.isNorth),junction.altitude))
			local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
			if vertNeighbor ~= nil then
				print(string.format("vert neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",vertNeighbor.x,vertNeighbor.y,tostring(vertNeighbor.isNorth),vertNeighbor.altitude))
			end
			local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
			if westNeighbor ~= nil then
				print(string.format("west neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",westNeighbor.x,westNeighbor.y,tostring(westNeighbor.isNorth),westNeighbor.altitude))
			end
			local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
			if eastNeighbor ~= nil then
				print(string.format("east neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",eastNeighbor.x,eastNeighbor.y,tostring(eastNeighbor.isNorth),eastNeighbor.altitude))
			end
			riverTest.data[i] = 1.0
			lakesFound = true
		end
		if self:isLake(self.riverData[i].southJunction) then
			local junction = self.riverData[i].southJunction
			print(string.format("lake found at (%d, %d) isNorth = %s, altitude = %.12f!",junction.x,junction.y,tostring(junction.isNorth),junction.altitude))
			local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
			if vertNeighbor ~= nil then
				print(string.format("vert neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",vertNeighbor.x,vertNeighbor.y,tostring(vertNeighbor.isNorth),vertNeighbor.altitude))
			end
			local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
			if westNeighbor ~= nil then
				print(string.format("west neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",westNeighbor.x,westNeighbor.y,tostring(westNeighbor.isNorth),westNeighbor.altitude))
			end
			local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
			if eastNeighbor ~= nil then
				print(string.format("east neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",eastNeighbor.x,eastNeighbor.y,tostring(eastNeighbor.isNorth),eastNeighbor.altitude))
			end
			riverTest.data[i] = 1.0
			lakesFound = true
		end
	end

	if lakesFound then
		print("###ERROR### - Failed to siltify lakes. check logs")
		--g_ElevationMap:Save4("g_ElevationMap(SiltifyLakes).csv")
	end
]]-- -Bobert13
--	riverTest:Normalize()
--	riverTest:Save("riverTest.csv")
end
-------------------------------------------------------------------------------------------
function RiverMap:SetFlowDestinations()
	junctionList = {}
	local i = 0
	for y = 0,g_ElevationMap.height - 1,1 do
		for x = 0,g_ElevationMap.width - 1,1 do
			table.insert(junctionList,self.riverData[i].northJunction)
			table.insert(junctionList,self.riverData[i].southJunction)
			i=i+1
		end
	end

	table.sort(junctionList,function (a,b) return a.altitude > b.altitude end)

	for n=1,#junctionList do
		local junction = junctionList[n]
		local validList = self:GetValidFlows(junction)
		if #validList > 0 then
			local choice = PWRandInt(1,#validList)
			junction.flow = validList[choice]
		else
			junction.flow = mc.NOFLOW
		end
	end
end
-------------------------------------------------------------------------------------------
function RiverMap:GetValidFlows(junction)
	local validList = {}
	for dir = mc.WESTFLOW,mc.VERTFLOW,1 do
		neighbor = self:GetJunctionNeighbor(dir,junction)
		if neighbor ~= nil and neighbor.altitude < junction.altitude then
			table.insert(validList,dir)
		end
	end
	return validList
end
-------------------------------------------------------------------------------------------
function RiverMap:IsTouchingOcean(junction)

	if g_ElevationMap:IsBelowSeaLevel(junction.x,junction.y) then
		return true
	end
	local westNeighbor = self:GetRiverHexNeighbor(junction,true)
	local eastNeighbor = self:GetRiverHexNeighbor(junction,false)

	if westNeighbor == nil or g_ElevationMap:IsBelowSeaLevel(westNeighbor.x,westNeighbor.y) then
		return true
	end
	if eastNeighbor == nil or g_ElevationMap:IsBelowSeaLevel(eastNeighbor.x,eastNeighbor.y) then
		return true
	end
	return false
end
-------------------------------------------------------------------------------------------
function RiverMap:SetRiverSizes(rainfall_map)
	local junctionList = {} --only include junctions not touching ocean in this list
	local i = 0
	for y = 0,g_ElevationMap.height - 1,1 do
		for x = 0,g_ElevationMap.width - 1,1 do
			if not self:IsTouchingOcean(self.riverData[i].northJunction) then
				table.insert(junctionList,self.riverData[i].northJunction)
			end
			if not self:IsTouchingOcean(self.riverData[i].southJunction) then
				table.insert(junctionList,self.riverData[i].southJunction)
			end
			i=i+1
		end
	end

	table.sort(junctionList,function (a,b) return a.altitude > b.altitude end)

	for n=1,#junctionList do
		local junction = junctionList[n]
		local nextJunction = junction
		local i = g_ElevationMap:GetIndex(junction.x,junction.y)
		while true do
			nextJunction.size = (nextJunction.size + rainfall_map.data[i]) * mc.riverRainCheatFactor
			if nextJunction.flow == mc.NOFLOW or self:IsTouchingOcean(nextJunction) then
				nextJunction.size = 0.0
				break
			end
			nextJunction = self:GetJunctionNeighbor(nextJunction.flow,nextJunction)
		end
	end

	--now sort by river size to find river threshold
	table.sort(junctionList,function (a,b) return a.size > b.size end)
	local riverIndex = math.floor(mc.riverPercent * #junctionList)
	self.riverThreshold = junctionList[riverIndex].size
		if self.riverThreshold < mc.minRiverSize then
			self.riverThreshold = mc.minRiverSize
		end
	--print(string.format("river threshold = %f",self.riverThreshold))

--~ 	local river_map = FloatMap:New(g_ElevationMap.width,g_ElevationMap.height,g_ElevationMap.xWrap,g_ElevationMap.yWrap)
--~ 	for y = 0,g_ElevationMap.height - 1,1 do
--~ 		for x = 0,g_ElevationMap.width - 1,1 do
--~ 			local i = g_ElevationMap:GetIndex(x,y)
--~ 			river_map.data[i] = math.max(self.riverData[i].northJunction.size,self.riverData[i].southJunction.size)
--~ 		end
--~ 	end
--~ 	river_map:Normalize()
	--river_map:Save("riverSizeMap.csv")
end
-------------------------------------------------------------------------------------------
--This function returns the flow directions needed by civ
function RiverMap:GetFlowDirections(x,y)
	--print(string.format("Get flow dirs for %d,%d",x,y))
	local i = g_ElevationMap:GetIndex(x,y)

	local WOfRiver = FlowDirectionTypes.NO_FLOWDIRECTION
	local xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.NE)
	local ii = g_ElevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].southJunction.flow == mc.VERTFLOW and self.riverData[ii].southJunction.size > self.riverThreshold then
		--print(string.format("--NE(%d,%d) south flow=%d, size=%f",xx,yy,self.riverData[ii].southJunction.flow,self.riverData[ii].southJunction.size))
		WOfRiver = FlowDirectionTypes.FLOWDIRECTION_SOUTH
	end
	xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.SE)
	ii = g_ElevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].northJunction.flow == mc.VERTFLOW and self.riverData[ii].northJunction.size > self.riverThreshold then
		--print(string.format("--SE(%d,%d) north flow=%d, size=%f",xx,yy,self.riverData[ii].northJunction.flow,self.riverData[ii].northJunction.size))
		WOfRiver = FlowDirectionTypes.FLOWDIRECTION_NORTH
	end

	local NWOfRiver = FlowDirectionTypes.NO_FLOWDIRECTION
	xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.SE)
	ii = g_ElevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].northJunction.flow == mc.WESTFLOW and self.riverData[ii].northJunction.size > self.riverThreshold then
		NWOfRiver = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST
	end
	if self.riverData[i].southJunction.flow == mc.EASTFLOW and self.riverData[i].southJunction.size > self.riverThreshold then
		NWOfRiver = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST
	end

	local NEOfRiver = FlowDirectionTypes.NO_FLOWDIRECTION
	xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.SW)
	ii = g_ElevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].northJunction.flow == mc.EASTFLOW and self.riverData[ii].northJunction.size > self.riverThreshold then
		NEOfRiver = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST
	end
	if self.riverData[i].southJunction.flow == mc.WESTFLOW and self.riverData[i].southJunction.size > self.riverThreshold then
		NEOfRiver = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST
	end

	return WOfRiver,NWOfRiver,NEOfRiver
end
-------------------------------------------------------------------------------------------
--RiverHex class
-------------------------------------------------------------------------------------------
RiverHex = inheritsFrom(nil)

function RiverHex:New(x,y)
	local new_inst = {}
	setmetatable(new_inst, {__index = RiverHex});

	new_inst.x = x
	new_inst.y = y
	new_inst.northJunction = RiverJunction:New(x,y,true)
	new_inst.southJunction = RiverJunction:New(x,y,false)

	return new_inst
end
-------------------------------------------------------------------------------------------
--RiverJunction class
-------------------------------------------------------------------------------------------
RiverJunction = inheritsFrom(nil)

function RiverJunction:New(x,y,isNorth)
	local new_inst = {}
	setmetatable(new_inst, {__index = RiverJunction});

	new_inst.x = x
	new_inst.y = y
	new_inst.isNorth = isNorth
	new_inst.altitude = 0.0
	new_inst.flow = mc.NOFLOW
	new_inst.size = 0.0

	return new_inst
end
-------------------------------------------------------------------------------------------
--Global functions
-------------------------------------------------------------------------------------------
function GenerateTwistedPerlinMap(width, height, xWrap, yWrap,minFreq,maxFreq,varFreq)
	local inputNoise = FloatMap:New(width,height,xWrap,yWrap)
	inputNoise:GenerateNoise()
	inputNoise:Normalize()

	local freqMap = FloatMap:New(width,height,xWrap,yWrap)
	local i = 0
	for y = 0, freqMap.height - 1,1 do
		for x = 0,freqMap.width - 1,1 do
			local odd = y % 2
			local xx = x + odd * 0.5
			freqMap.data[i] = GetPerlinNoise(xx,y * mc.YtoXRatio,freqMap.width,freqMap.height * mc.YtoXRatio,varFreq,1.0,0.1,8,inputNoise)
			i=i+1
		end
	end
	freqMap:Normalize()
--	freqMap:Save("freqMap.csv")

	local twistMap = FloatMap:New(width,height,xWrap,yWrap)
	i = 0
	for y = 0, twistMap.height - 1,1 do
		for x = 0,twistMap.width - 1,1 do
			local freq = freqMap.data[i] * (maxFreq - minFreq) + minFreq
			local mid = (maxFreq - minFreq)/2 + minFreq
			local coordScale = freq/mid
			local offset = (1.0 - coordScale)/mid
			--print("1-coordscale = " .. (1.0 - coordScale) .. ", offset = " .. offset)
			local ampChange = 0.85 - freqMap.data[i] * 0.5
			local odd = y % 2
			local xx = x + odd * 0.5
			twistMap.data[i] = GetPerlinNoise(xx + offset,(y + offset) * mc.YtoXRatio,twistMap.width,twistMap.height * mc.YtoXRatio,mid,1.0,ampChange,8,inputNoise)
			i=i+1
		end
	end

	twistMap:Normalize()
	--twistMap:Save("twistMap.csv")
	return twistMap
end
-------------------------------------------------------------------------------------------
function ShuffleList(list)
	local len = #list
	for i=0,len - 1,1 do
		local k = PWRandInt(0,len-1)
		list[i], list[k] = list[k], list[i]
	end
end
-------------------------------------------------------------------------------------------
function ShuffleList2(list)
	local len = #list
	for i=1,len ,1 do
		local k = PWRandInt(1,len)
		list[i], list[k] = list[k], list[i]
	end
end
-------------------------------------------------------------------------------------------
function GenerateMountainMap(width,height,xWrap,yWrap,initFreq)
	local inputNoise = FloatMap:New(width,height,xWrap,yWrap)
	inputNoise:GenerateBinaryNoise()
	inputNoise:Normalize()
	local inputNoise2 = FloatMap:New(width,height,xWrap,yWrap)
	inputNoise2:GenerateNoise()
	inputNoise2:Normalize()

	local mountainMap = FloatMap:New(width,height,xWrap,yWrap)
	local stdDevMap = FloatMap:New(width,height,xWrap,yWrap)
	local noiseMap = FloatMap:New(width,height,xWrap,yWrap)
	local i = 0
	for y = 0, mountainMap.height - 1,1 do
		for x = 0,mountainMap.width - 1,1 do
			local odd = y % 2
			local xx = x + odd * 0.5
			mountainMap.data[i] = GetPerlinNoise(xx,y * mc.YtoXRatio,mountainMap.width,mountainMap.height * mc.YtoXRatio,initFreq,1.0,0.4,8,inputNoise)
			noiseMap.data[i] = GetPerlinNoise(xx,y * mc.YtoXRatio,mountainMap.width,mountainMap.height * mc.YtoXRatio,initFreq,1.0,0.4,8,inputNoise2)
			stdDevMap.data[i] = mountainMap.data[i]
			i=i+1
		end
	end
	mountainMap:Normalize()
	stdDevMap:Deviate(7)
	stdDevMap:Normalize()
	--stdDevMap:Save("stdDevMap.csv")
	--mountainMap:Save("mountainCloud.csv")
	noiseMap:Normalize()
	--noiseMap:Save("noiseMap.csv")

	local moundMap = FloatMap:New(width,height,xWrap,yWrap)
	i = 0
	for y = 0, mountainMap.height - 1,1 do
		for x = 0,mountainMap.width - 1,1 do
			local val = mountainMap.data[i]
			moundMap.data[i] = (math.sin(val*math.pi*2-math.pi*0.5)*0.5+0.5) * GetAttenuationFactor(mountainMap,x,y)
			if val < 0.5 then
				val = val^1 * 4
			else
				val = (1 - val)^1 * 4
			end
			--mountainMap.data[i] = val
			mountainMap.data[i] = moundMap.data[i]
			i=i+1
		end
	end
	mountainMap:Normalize()
	--mountainMap:Save("premountMap.csv")
	--moundMap:Save("moundMap.csv")
	i = 0
	for y = 0, mountainMap.height - 1,1 do
		for x = 0,mountainMap.width - 1,1 do
			local val = mountainMap.data[i]
			--mountainMap.data[i] = (math.sin(val * 2 * math.pi + math.pi * 0.5)^8 * val) + moundMap.data[i] * 2 + noiseMap.data[i] * 0.6
			mountainMap.data[i] = (math.sin(val * 3 * math.pi + math.pi * 0.5)^16 * val)^0.5
			if mountainMap.data[i] > 0.2 then
				mountainMap.data[i] = 1.0
			else
				mountainMap.data[i] = 0.0
			end
			i=i+1
		end
	end
	--mountainMap:Save("premountMap.csv")

	local stdDevThreshold = stdDevMap:FindThresholdFromPercent(mc.landPercent,true,false)
	i=0
	for y = 0, mountainMap.height - 1,1 do
		for x = 0,mountainMap.width - 1,1 do
			local val = mountainMap.data[i]
			local dev = 2.0 * stdDevMap.data[i] - 2.0 * stdDevThreshold
			--mountainMap.data[i] = (math.sin(val * 2 * math.pi + math.pi * 0.5)^8 * val) + moundMap.data[i] * 2 + noiseMap.data[i] * 0.6
			mountainMap.data[i] = (val + moundMap.data[i]) * dev
			i=i+1
		end
	end

	mountainMap:Normalize()
	--mountainMap:Save("mountainMap.csv")
	return mountainMap
end
-------------------------------------------------------------------------------------------
function waterMatch(x,y)
	if g_ElevationMap:IsBelowSeaLevel(x,y) then
		return true
	end
	return false
end
-------------------------------------------------------------------------------------------
function GetAttenuationFactor(map,x,y)
	local southY = map.height * mc.southAttenuationRange
	local southRange = map.height * mc.southAttenuationRange
	local yAttenuation = 1.0
	if y < southY then
		yAttenuation = mc.southAttenuationFactor + (y/southRange) * (1.0 - mc.southAttenuationFactor)
	end

	local northY = map.height - (map.height * mc.northAttenuationRange)
	local northRange = map.height * mc.northAttenuationRange
	if y > northY then
		yAttenuation = mc.northAttenuationFactor + ((map.height - y)/northRange) * (1.0 - mc.northAttenuationFactor)
	end

	local eastY = map.width - (map.width * mc.eastAttenuationRange)
	local eastRange = map.width * mc.eastAttenuationRange
	local xAttenuation = 1.0
	if x > eastY then
		xAttenuation = mc.eastAttenuationFactor + ((map.width - x)/eastRange) * (1.0 - mc.eastAttenuationFactor)
	end

	local westY = map.width * mc.westAttenuationRange
	local westRange = map.width * mc.westAttenuationRange
	if x < westY then
		xAttenuation = mc.westAttenuationFactor + (x/westRange) * (1.0 - mc.westAttenuationFactor)
	end

	return yAttenuation * xAttenuation
end
-------------------------------------------------------------------------------------------
function GenerateElevationMap(width,height,xWrap,yWrap)
	local twistMinFreq = 128/width * mc.twistMinFreq --0.02/128
	local twistMaxFreq = 128/width * mc.twistMaxFreq --0.12/128
	local twistVar = 128/width * mc.twistVar --0.042/128
	local mountainFreq = 128/width * mc.mountainFreq --0.05/128
	local twistMap = GenerateTwistedPerlinMap(width,height,xWrap,yWrap,twistMinFreq,twistMaxFreq,twistVar)
	local mountainMap = GenerateMountainMap(width,height,xWrap,yWrap,mountainFreq)
	local g_ElevationMap = ElevationMap:New(width,height,xWrap,yWrap)
	local i = 0
	for y = 0,height - 1,1 do
		for x = 0,width - 1,1 do
			local tVal = twistMap.data[i]
			tVal = (math.sin(tVal*math.pi-math.pi*0.5)*0.5+0.5)^0.25 --this formula adds a curve flattening the extremes
			g_ElevationMap.data[i] = (tVal + ((mountainMap.data[i] * 2) - 1) * mc.mountainWeight)
			i=i+1
		end
	end

	g_ElevationMap:Normalize()

	--attentuation should not break normalization
	i = 0
	for y = 0,height - 1,1 do
		for x = 0,width - 1,1 do
			local attenuationFactor = GetAttenuationFactor(g_ElevationMap,x,y)
			g_ElevationMap.data[i] = g_ElevationMap.data[i] * attenuationFactor
			i=i+1
		end
	end

	g_ElevationMap.seaLevelThreshold = g_ElevationMap:FindThresholdFromPercent(mc.landPercent,true,false)

	return g_ElevationMap
end
-------------------------------------------------------------------------------------------
function FillInLakes()
	local max_lake_size = 6
	local areaMap = PWAreaMap:New(g_ElevationMap.width,g_ElevationMap.height,g_ElevationMap.wrapX,g_ElevationMap.wrapY)
	areaMap:DefineAreas(waterMatch)
	for i=1,#areaMap.areaList,1 do
		local area = areaMap.areaList[i]
		if area.trueMatch and area.size <= max_lake_size then
			for n = 0,areaMap.length,1 do
				if areaMap.data[n] == area.id then
					g_ElevationMap.data[n] = g_ElevationMap.seaLevelThreshold
				end
			end
		end
	end
end
-------------------------------------------------------------------------------------------
function GenerateTempMaps(elevation_map)

	local aboveSeaLevelMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	local i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			if elevation_map:IsBelowSeaLevel(x,y) then
				aboveSeaLevelMap.data[i] = 0.0
			else
				aboveSeaLevelMap.data[i] = elevation_map.data[i] - elevation_map.seaLevelThreshold
			end
			i=i+1
		end
	end
	aboveSeaLevelMap:Normalize()
	--aboveSeaLevelMap:Save("aboveSeaLevelMap.csv")

	local summerMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	local zenith = mc.tropicLatitudes
	local topTempLat = mc.topLatitude + zenith
	local bottomTempLat = mc.bottomLatitude
	local latRange = topTempLat - bottomTempLat
	i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			local lat = summerMap:GetLatitudeForY(y)
			--print("y=" .. y ..",lat=" .. lat)
			local latPercent = (lat - bottomTempLat)/latRange
			--print("latPercent=" .. latPercent)
			local temp = (math.sin(latPercent * math.pi * 2 - math.pi * 0.5) * 0.5 + 0.5)
			if elevation_map:IsBelowSeaLevel(x,y) then
				temp = temp * mc.maxWaterTemp + mc.minWaterTemp
			end
			summerMap.data[i] = temp
			i=i+1
		end
	end
	summerMap:Smooth(math.floor(elevation_map.width/8))
	summerMap:Normalize()

	local winterMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	zenith = -mc.tropicLatitudes
	topTempLat = mc.topLatitude
	bottomTempLat = mc.bottomLatitude + zenith
	latRange = topTempLat - bottomTempLat
	i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			local lat = winterMap:GetLatitudeForY(y)
			local latPercent = (lat - bottomTempLat)/latRange
			local temp = math.sin(latPercent * math.pi * 2 - math.pi * 0.5) * 0.5 + 0.5
			if elevation_map:IsBelowSeaLevel(x,y) then
				temp = temp * mc.maxWaterTemp + mc.minWaterTemp
			end
			winterMap.data[i] = temp
			i=i+1
		end
	end
	winterMap:Smooth(math.floor(elevation_map.width/8))
	winterMap:Normalize()

	local temperature_map = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			temperature_map.data[i] = (winterMap.data[i] + summerMap.data[i]) * (1.0 - 0.5 * aboveSeaLevelMap.data[i])
			--temperature_map.data[i] = (winterMap.data[i] + summerMap.data[i]) * (1.0 - aboveSeaLevelMap.data[i])
			i=i+1
		end
	end
	temperature_map:Normalize()

	return summerMap,winterMap,temperature_map
end
-------------------------------------------------------------------------------------------
function GenerateRainfallMap(elevation_map)
	local summerMap,winterMap,temperature_map = GenerateTempMaps(elevation_map)
	--summerMap:Save("summerMap.csv")
	--winterMap:Save("winterMap.csv")
	--temperature_map:Save("temperature_map.csv")
	local geoMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	local i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			local lat = elevation_map:GetLatitudeForY(y)
			local pressure = elevation_map:GetGeostrophicPressure(lat)
			geoMap.data[i] = pressure
			--print(string.format("pressure for (%d,%d) is %.8f",x,y,pressure))
			i=i+1
		end
	end
	geoMap:Normalize()
	--geoMap:Save("geoMap.csv")
	i = 0
	local sortedSummerMap = {}
	local sortedWinterMap = {}
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			sortedSummerMap[i + 1] = {x,y,summerMap.data[i]}
			sortedWinterMap[i + 1] = {x,y,winterMap.data[i]}
			i=i+1
		end
	end
	table.sort(sortedSummerMap, function (a,b) return a[3] < b[3] end)
	table.sort(sortedWinterMap, function (a,b) return a[3] < b[3] end)

	local sortedGeoMap = {}
	local xStart = 0
	local xStop = 0
	local yStart = 0
	local yStop = 0
	local incX = 0
	local incY = 0
	local geoIndex = 1
	local str = ""
	for zone=0,5,1 do
		local topY = elevation_map:GetYFromZone(zone,true)
		local bottomY = elevation_map:GetYFromZone(zone,false)
		if not (topY == -1 and bottomY == -1) then
			if topY == -1 then
				topY = elevation_map.height - 1
			end
			if bottomY == -1 then
				bottomY = 0
			end
			--print(string.format("topY = %d, bottomY = %d",topY,bottomY))
			local dir1,dir2 = elevation_map:GetGeostrophicWindDirections(zone)
			--print(string.format("zone = %d, dir1 = %d",zone,dir1))
			if (dir1 == mc.SW) or (dir1 == mc.SE) then
				yStart = topY
				yStop = bottomY --- 1
				incY = -1
			else
				yStart = bottomY
				yStop = topY --+ 1
				incY = 1
			end
			if dir2 == mc.W then
				xStart = elevation_map.width - 1
				xStop = 0---1
				incX = -1
			else
				xStart = 0
				xStop = elevation_map.width - 1
				incX = 1
			end
			--print(string.format("yStart = %d, yStop = %d, incY = %d",yStart,yStop,incY))
			--print(string.format("xStart = %d, xStop = %d, incX = %d",xStart,xStop,incX)

			for y = yStart,yStop ,incY do
				--print(string.format("y = %d",y))
				--each line should start on water to avoid vast areas without rain
				local xxStart = xStart
				local xxStop = xStop
				for xx = xStart,xStop, incX do
					local i = elevation_map:GetIndex(xx,y)
					if elevation_map:IsBelowSeaLevel(xx,y) then
						xxStart = xx
						xxStop = xx + (elevation_map.width - 1) * incX
						break
					end
				end
				for x = xxStart,xxStop,incX do
					local i = elevation_map:GetIndex(x,y)
					sortedGeoMap[geoIndex] = {x,y,geoMap.data[i]}
					geoIndex = geoIndex + 1
				end
			end
		end
	end
	--table.sort(sortedGeoMap, function (a,b) return a[3] < b[3] end)
	--print(#sortedGeoMap)
	--print(#geoMap.data)

	local rainfallSummerMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	local moistureMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	for i = 1,#sortedSummerMap,1 do
		local x = sortedSummerMap[i][1]
		local y = sortedSummerMap[i][2]
		DistributeRain(x,y,elevation_map,temperature_map,summerMap,rainfallSummerMap,moistureMap,false)
	end

	local rainfallWinterMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	local moistureMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	for i = 1,#sortedWinterMap,1 do
		local x = sortedWinterMap[i][1]
		local y = sortedWinterMap[i][2]
		DistributeRain(x,y,elevation_map,temperature_map,winterMap,rainfallWinterMap,moistureMap,false)
	end

	local rainfallGeostrophicMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	moistureMap = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	--print("----------------------------------------------------------------------------------------")
	--print("--GEOSTROPHIC---------------------------------------------------------------------------")
	--print("----------------------------------------------------------------------------------------")
	for i = 1,#sortedGeoMap,1 do
		local x = sortedGeoMap[i][1]
		local y = sortedGeoMap[i][2]
		DistributeRain(x,y,elevation_map,temperature_map,geoMap,rainfallGeostrophicMap,moistureMap,true)
	end
	--zero below sea level for proper percent threshold finding
	i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			if elevation_map:IsBelowSeaLevel(x,y) then
				rainfallSummerMap.data[i] = 0.0
				rainfallWinterMap.data[i] = 0.0
				rainfallGeostrophicMap.data[i] = 0.0
			end
			i=i+1
		end
	end

	rainfallSummerMap:Normalize()
	--rainfallSummerMap:Save("rainFallSummerMap.csv")
	rainfallWinterMap:Normalize()
	--rainfallWinterMap:Save("rainFallWinterMap.csv")
	rainfallGeostrophicMap:Normalize()
	--rainfallGeostrophicMap:Save("rainfallGeostrophicMap.csv")

	local rainfall_map = FloatMap:New(elevation_map.width,elevation_map.height,elevation_map.xWrap,elevation_map.yWrap)
	i = 0
	for y = 0,elevation_map.height - 1,1 do
		for x = 0,elevation_map.width - 1,1 do
			rainfall_map.data[i] = rainfallSummerMap.data[i] + rainfallWinterMap.data[i] + (rainfallGeostrophicMap.data[i] * mc.geostrophicFactor)
			i=i+1
		end
	end
	rainfall_map:Normalize()

	return rainfall_map, temperature_map
end
-------------------------------------------------------------------------------------------
function DistributeRain(x,y,elevation_map,temperature_map,pressureMap,rainfall_map,moistureMap,boolGeostrophic)

	local i = elevation_map:GetIndex(x,y)
	local upLiftSource = math.max(math.pow(pressureMap.data[i],mc.upLiftExponent),1.0 - temperature_map.data[i])
	--local str = string.format("geo=%s,x=%d, y=%d, srcPressure uplift = %f, upliftSource = %f",tostring(boolGeostrophic),x,y,math.pow(pressureMap.data[i],mc.upLiftExponent),upLiftSource)
	--print(str)
	if elevation_map:IsBelowSeaLevel(x,y) then
		moistureMap.data[i] = math.max(moistureMap.data[i], temperature_map.data[i])
		--print("water tile = true")
	end
	--print(string.format("moistureMap.data[i] = %f",moistureMap.data[i]))

	--make list of neighbors
	local nList = {}
	if boolGeostrophic then
		local zone = elevation_map:GetZone(y)
		local dir1,dir2 = elevation_map:GetGeostrophicWindDirections(zone)
		local x1,y1 = elevation_map:GetNeighbor(x,y,dir1)
		local ii = elevation_map:GetIndex(x1,y1)
		--neighbor must be on map and in same wind zone
		if ii >= 0 and (elevation_map:GetZone(y1) == elevation_map:GetZone(y)) then
			table.insert(nList,{x1,y1})
		end
		local x2,y2 = elevation_map:GetNeighbor(x,y,dir2)
		ii = elevation_map:GetIndex(x2,y2)
		if ii >= 0 then
			table.insert(nList,{x2,y2})
		end
	else
		for dir = 1,6,1 do
			local xx,yy = elevation_map:GetNeighbor(x,y,dir)
			local ii = elevation_map:GetIndex(xx,yy)
			if ii >= 0 and pressureMap.data[i] <= pressureMap.data[ii] then
				table.insert(nList,{xx,yy})
			end
		end
	end
	if #nList == 0 or boolGeostrophic and #nList == 1 then
		local cost = moistureMap.data[i]
		rainfall_map.data[i] = cost
		return
	end
	local moisturePerNeighbor = moistureMap.data[i]/#nList
	--drop rain and pass moisture to neighbors
	for n = 1,#nList,1 do
		local xx = nList[n][1]
		local yy = nList[n][2]
		local ii = elevation_map:GetIndex(xx,yy)
		local upLiftDest = math.max(math.pow(pressureMap.data[ii],mc.upLiftExponent),1.0 - temperature_map.data[ii])
		local cost = GetRainCost(upLiftSource,upLiftDest)
		local bonus = 0.0
		if (elevation_map:GetZone(y) == mc.NPOLAR or elevation_map:GetZone(y) == mc.SPOLAR) then
			bonus = mc.polarRainBoost
		end
		if boolGeostrophic and #nList == 2 then
			if n == 1 then
				moisturePerNeighbor = (1.0 - mc.geostrophicLateralWindStrength) * moistureMap.data[i]
			else
				moisturePerNeighbor = mc.geostrophicLateralWindStrength * moistureMap.data[i]
			end
		end
		--print(string.format("---xx=%d, yy=%d, destPressure uplift = %f, upLiftDest = %f, cost = %f, moisturePerNeighbor = %f, bonus = %f",xx,yy,math.pow(pressureMap.data[ii],mc.upLiftExponent),upLiftDest,cost,moisturePerNeighbor,bonus))
		rainfall_map.data[i] = rainfall_map.data[i] + cost * moisturePerNeighbor + bonus
		--pass to neighbor.
		--print(string.format("---moistureMap.data[ii] = %f",moistureMap.data[ii]))
		moistureMap.data[ii] = moistureMap.data[ii] + moisturePerNeighbor - (cost * moisturePerNeighbor)
		--print(string.format("---dropping %f rain",cost * moisturePerNeighbor + bonus))
		--print(string.format("---passing on %f moisture",moisturePerNeighbor - (cost * moisturePerNeighbor)))
	end

end
-------------------------------------------------------------------------------------------
function GetRainCost(upLiftSource,upLiftDest)
	return math.max(mc.minimumRainCost, mc.minimumRainCost + upLiftDest - upLiftSource)
end
-------------------------------------------------------------------------------------------
function GetDifferenceAroundHex(i)
	local avg = g_ElevationMap:GetAverageInHex(i,1)
	return g_ElevationMap.data[i] - avg
end
-------------------------------------------------------------------------------------------
function PlacePossibleOasis()
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"]
	local terrainPlains	= GameInfoTypes["TERRAIN_PLAINS"]
	local terrainTundra	= GameInfoTypes["TERRAIN_TUNDRA"]
	local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"]
	local featureFloodPlains = FeatureTypes.FEATURE_FLOOD_PLAINS
	local featureOasis = FeatureTypes.FEATURE_OASIS
	local plotMountain = PlotTypes.PLOT_MOUNTAIN
	local oasisTotal = 0
	local W,H = Map.GetGridSize()
	local WH = W*H
	ShuffleList2(g_DesertTab)
	for k=1,#g_DesertTab do
		local i = g_DesertTab[k]
		local plot = Map.GetPlotByIndex(i) --Sets the candidate plot.
		local tiles = GetSpiral(i,3) --Creates a table of all coordinates within 3 tiles of the candidate plot.
		local desertCount = 0
		local canPlace = true
		for n=1,7 do --Analyzes the first 7 entries in the table. These will all be adjacent to the candidate plot or thep candidate itself.
			local ii = tiles[n]
			if ii ~= -1 then
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetFeatureType() == featureFloodPlains then
					canPlace = false
					break
				elseif nPlot:IsWater() then
					canPlace = false
					break
				elseif nPlot:GetTerrainType() == terrainDesert then
					if nPlot:GetPlotType() ~= plotMountain then
						desertCount = desertCount + 1
					end
				end
			end
		end
		if desertCount < 4 then
			canPlace = false
		end
		if canPlace then
			local foodCount = 0
			for n=1,19 do --Analyzes the first 19 entries in the table. These will all be the candidate plot itself or within two tiles of it.
				local ii = tiles[n]
				if ii ~= -1 then
					local nPlot = Map.GetPlotByIndex(ii)
					if nPlot:GetPlotType() ~= PlotTypes.PLOT_HILLS then
						if nPlot:GetTerrainType() == terrainGrass or nPlot:IsRiver() then
							foodCount = foodCount + 2
						elseif nPlot:GetTerrainType() == terrainPlains or nPlot:GetTerrainType() == terrainTundra or nPlot:IsWater() then
							foodCount = foodCount + 1
						elseif nPlot:GetFeatureType() == featureOasis then
							foodCount = foodCount + mc.OasisThreshold --Prevents Oases from spawning within two tiles of eachother -Bobert13
						end
					elseif nPlot:IsRiver() then --Hills on a river. -Bobert13
						foodCount = foodCount + 1
					end
				end
			end
			if foodCount < mc.OasisThreshold then
				local oasisCount = 0
				local doplace = true
				for n=20,#tiles do --Analyzes the LAST 18 entries in the table. These will all be in the third ring of tiles around the candidate plot.
					local ii = tiles[n]
					if ii ~= -1 then
						local nPlot = Map.GetPlotByIndex(ii)
						if nPlot:GetFeatureType() == featureOasis then
							oasisCount = oasisCount+1
						end
					end
				end
				if oasisCount == 1 then
					local roll = PWRandInt(0,1)
					if roll == 1 then
						doplace = false
					end
				elseif oasisCount > 1 then
					doplace = false
				end
				if doplace then
					--local x = i%W
					--local y = (i-x)/W
					--print(string.format("---Placing Oasis at (%d,%d)",x,y))
					plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
					plot:SetFeatureType(featureOasis,-1)
					oasisTotal = oasisTotal +1
				end
			end
		end
	end
	print(string.format("Placed %d Oases. - PerfectWorld3",oasisTotal))
end
-------------------------------------------------------------------------------------------
function PlacePossibleIce(i,W)
	local plot = Map.GetPlotByIndex(i)
	local x = i%W
	local y = (i-x)/W
	if plot:IsWater() then
		local temp = g_TemperatureMap.data[i]
		local latitude = g_TemperatureMap:GetLatitudeForY(y)
		--local randval = PWRand() * (mc.iceMaxTemperature - mc.minWaterTemp) + mc.minWaterTemp * 2
		local randvalNorth = PWRand() * (mc.iceNorthLatitudeLimit - mc.topLatitude) + mc.topLatitude - 3
		local randvalSouth = PWRand() * (mc.bottomLatitude - mc.iceSouthLatitudeLimit) + mc.iceSouthLatitudeLimit + 3
		--print(string.format("lat = %f, randvalNorth = %f, randvalSouth = %f",latitude,randvalNorth,randvalSouth))
		if latitude > randvalNorth  or latitude < randvalSouth then
			TerrainBuilder.SetFeatureType(plot, g_FEATURE_ICE);
		end
	end
end
-------------------------------------------------------------------------------------------
--function GetMapInitData(worldSize)
--	local worldsizes = {
--		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {42, 26},
--		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {52, 32},
--		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {64, 40},
--		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {84, 52},
--		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {104, 64},
--		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {128, 80}
--		}
--	if Map.GetCustomOption(6) == 2 then
--		-- Enlarge terra-style maps to create expansion room on the new world
--		worldsizes = {
--		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {52, 32},
--		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {64, 40},
--		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {84, 52},
--		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {104, 64},
--		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {122, 76},
--		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {144, 90},
--		}
--	end
--	local grid_size = worldsizes[worldSize];
--	--
--	local world = GameInfo.Worlds[worldSize];
--	if(world ~= nil) then
--	return {
--		Width = grid_size[1],
--		Height = grid_size[2],
--		WrapX = true,
--	};
--    end
--end
-------------------------------------------------------------------------------------------
--ShiftMap Class
-------------------------------------------------------------------------------------------
function ShiftMaps()
	--local stripRadius = self.stripRadius;
	local shift_x = 0
	local shift_y = 0

	shift_x = DetermineXShift()
	
	ShiftMapsBy(shift_x, shift_y)
end
-------------------------------------------------------------------------------------------	
function ShiftMapsBy(xshift, yshift)	
	local W, H = Map.GetGridSize();
	if(xshift > 0 or yshift > 0) then
		local Shift = {}
		local iDestI = 0
		for iDestY = 0, H-1 do
			for iDestX = 0, W-1 do
				local iSourceX = (iDestX + xshift) % W;
				--local iSourceY = (iDestY + yshift) % H; -- If using yshift, enable this and comment out the faster line below. - Bobert13
				local iSourceY = iDestY
				local iSourceI = W * iSourceY + iSourceX
				Shift[iDestI] = g_ElevationMap.data[iSourceI]
				--print(string.format("Shift:%d,	%f	|	eMap:%d,	%f",iDestI,Shift[iDestI],iSourceI,g_ElevationMap.data[iSourceI]))
				iDestI = iDestI+1
			end
		end
		g_ElevationMap.data = Shift --It's faster to do one large table operation here than it is to do thousands of small operations to set up a copy of the input table at the beginning. -Bobert13
		return g_ElevationMap
	end
end
-------------------------------------------------------------------------------------------
function DetermineXShift()
	--[[ This function will align the most water-heavy vertical portion of the map with the 
	vertical map edge. This is a form of centering the landmasses, but it emphasizes the
	edge not the middle. If there are columns completely empty of land, these will tend to
	be chosen as the new map edge, but it is possible for a narrow column between two large 
	continents to be passed over in favor of the thinnest section of a continent, because
	the operation looks at a group of columns not just a single column, then picks the 
	center of the most water heavy group of columns to be the new vertical map edge. ]]--

	-- First loop through the map columns and record land plots in each column.
	local gridWidth, gridHeight = Map.GetGridSize();
	local land_totals = {};
	for x = 0, gridWidth - 1 do
		local current_column = 0;
		for y = 0, gridHeight - 1 do
			--local i = y * gridWidth + x + 1;
			if not g_ElevationMap:IsBelowSeaLevel(x,y) then
				current_column = current_column + 1;
			end
		end
		table.insert(land_totals, current_column);
	end
	
	-- Now evaluate column groups, each record applying to the center column of the group.
	local column_groups = {};
	-- Determine the group size in relation to map width.
	local group_radius = 3;
	-- Measure the groups.
	for column_index = 1, gridWidth do
		local current_group_total = 0;
		--for current_column = column_index - group_radius, column_index + group_radius do
		--Changed how group_radius works to get groups of four. -Bobert13
		for current_column = column_index, column_index + group_radius do
			local current_index = current_column % gridWidth;
			if current_index == 0 then -- Modulo of the last column will be zero; this repairs the issue.
				current_index = gridWidth;
			end
			current_group_total = current_group_total + land_totals[current_index];
		end
		table.insert(column_groups, current_group_total);
	end
	
	-- Identify the group with the least amount of land in it.
	local best_value = gridHeight * (group_radius + 1); -- Set initial value to max possible.
	local best_group = 1; -- Set initial best group as current map edge.
	for column_index, group_land_plots in ipairs(column_groups) do
		if group_land_plots < best_value then
			best_value = group_land_plots;
			best_group = column_index;
		end
	end
	
	-- Determine X Shift	
	local x_shift = best_group + 2;
	if x_shift == gridWidth then
		x_shift = 0
	elseif x_shift == gridWidth+1 then
		x_shift = 1
	end

	return x_shift;
end
------------------------------------------------------------------------------
--DiffMap Class
------------------------------------------------------------------------------
--Seperated this from PWGeneratePlotTypes() to use it in other functions. -Bobert13

DiffMap = inheritsFrom(FloatMap)

function GenerateDiffMap(width,height,xWrap,yWrap)
	DiffMap = FloatMap:New(width,height,xWrap,yWrap)
	local i = 0
	for y = 0, height - 1,1 do
		for x = 0,width - 1,1 do
			if g_ElevationMap:IsBelowSeaLevel(x,y) then
				DiffMap.data[i] = 0.0
			else
				DiffMap.data[i] = GetDifferenceAroundHex(i)
			end
			i=i+1
		end
	end

	DiffMap:Normalize()
	i = 0
	for y = 0, height - 1,1 do
		for x = 0,width - 1,1 do
			if g_ElevationMap:IsBelowSeaLevel(x,y) then
				DiffMap.data[i] = 0.0
			else
				DiffMap.data[i] = DiffMap.data[i] + g_ElevationMap.data[i] * 1.1
			end
			i=i+1
		end
	end

	DiffMap:Normalize()
	return DiffMap
end
-------------------------------------------------------------------------------------------

------------------------------------------------------------------------------
function AddLakes()
	--print("Adding Lakes - YAPD")
	local Desert	= GameInfoTypes["TERRAIN_DESERT"]
	local Plains	= GameInfoTypes["TERRAIN_PLAINS"]
	local Snow		= GameInfoTypes["TERRAIN_SNOW"]
	local Tundra	= GameInfoTypes["TERRAIN_TUNDRA"]
	local Grass		= GameInfoTypes["TERRAIN_GRASS"]
	local W, H = Map.GetGridSize()
	local WOfRiver, NWOfRiver, NEOfRiver = nil
	local numLakes = 0
	local LakeUntil = H/10
	
	local iters = 0
	while numLakes < LakeUntil do
		local k = 1
		for n = 1,#g_LandTab do
			local i = g_LandTab[k]
			local x = i%W
			local y = (i-x)/W
			local plot = Map.GetPlotByIndex(i)
			if not plot:IsCoastalLand() then
				if not plot:IsRiver() then
					if not plot:GetTerrainType() == Desert then
						local r = PWRandInt(0,2)
						if r == 0 then
							--print(string.format("adding lake at (%d,%d)",x,y))
							local terrain = plot:GetTerrainType()
							if terrain == Grass then
								for z=1,#g_GrassTab,1 do if i == g_GrassTab[z] then table.remove(g_GrassTab, z) end end
							elseif terrain == Plains then
								for z=1,#g_PlainsTab,1 do if i == g_PlainsTab[z] then table.remove(g_PlainsTab, z) end end
							elseif terrain == Tundra then
								for z=1,#g_TundraTab,1 do if i == g_TundraTab[z] then table.remove(g_TundraTab, z) end end
							elseif terrain == Snow then
								for z=1,#g_SnowTab,1 do if i == g_SnowTab[z] then table.remove(g_SnowTab, z) end end
							else 
								print("Error - could not find index in any terrain table during AddLakes(). g_LandTab must be getting buggered up...")
							end
							plot:SetArea(-1)
							plot:SetPlotType(PlotTypes.PLOT_OCEAN, true, true)
							numLakes = numLakes + 1
							table.remove(g_LandTab, k)
							k=k-1
						end
					end
				end
			end
			k=k+1
		end
		iters = iters+1
		if iters > 499 then
			--print(string.format("Could not meet lake quota after %d iterations. - PerfectWorld3",iters))
			break
		end
	end
	
	if numLakes > 0 then
		print(string.format("Added %d lakes. - PerfectWorld3",numLakes))
		Map.CalculateAreas();
	end
end
------------------------------------------------------------------------------
function Cleanup()	
	--now we fix things up so that the border of tundra and ice regions are hills
	--this looks a bit more believable. Also keep desert away from tundra and ice
	--by turning it into plains
	
	--Moved this entire section because some of the calls require features and rivers
	--to be placed in order for them to work properly.
	--Got rid of the Hills bit because I like flat Snow/Tundra. Also added
	--a few terrain matching sections - Bobert13
	local W, H = Map.GetGridSize();
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
	local terrainPlains	= GameInfoTypes["TERRAIN_PLAINS"];
	local terrainSnow	= GameInfoTypes["TERRAIN_SNOW"];
	local terrainTundra	= GameInfoTypes["TERRAIN_TUNDRA"];
	local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"];
	local featureIce = FeatureTypes.FEATURE_ICE
	local featureOasis = FeatureTypes.FEATURE_OASIS
	local featureMarsh = FeatureTypes.FEATURE_MARSH
	local featureFloodPlains = FeatureTypes.FEATURE_FLOOD_PLAINS
	local nofeature = FeatureTypes.NO_FEATURE
	-- Gets rid of stray Snow tiles and replaces them with Tundra; also softens rivers in snow -Bobert13
	local k = 1
	for n=1,#g_SnowTab do
		local i = g_SnowTab[k]
		local x = i%W
		local y = (i-x)/W
		local plot = Map.GetPlotByIndex(i)
		if plot:IsRiver() then
			plot:SetTerrainType(terrainTundra, true, true)
			table.insert(g_TundraTab,i)
			table.remove(g_SnowTab,k)
			k=k-1
		else
			local tiles = GetCircle(i,1)
			local snowCount = 0
			local grassCount = 0
			for n=1,#tiles do
				local ii = tiles[n]
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetTerrainType() == terrainGrass then
					grassCount = grassCount + 1
				elseif nPlot:GetTerrainType() == terrainSnow then
					snowCount = snowCount + 1
				end
			end
			if snowCount == 1 or grassCount == 2 or (g_ElevationMap:GetLatitudeForY(y) < (mc.iceNorthLatitudeLimit - H/5) and g_ElevationMap:GetLatitudeForY(y) > (mc.iceSouthLatitudeLimit + H/5)) then
				plot:SetTerrainType(terrainTundra,true,true)
				table.insert(g_TundraTab,i)
				table.remove(g_SnowTab,k)
				k=k-1
			elseif grassCount >= 3 then
				plot:SetTerrainType(terrainPlains,true,true)
				table.insert(g_PlainsTab,i)
				table.remove(g_SnowTab,k)
				k=k-1
			end
		end
		k=k+1
	end
	if not mc.simpleCleanup then
		--Gets rid of strips of plains in the middle of deserts. -Bobert 13
		k = 1
		for n=1,#g_PlainsTab do
			local i = g_PlainsTab[k]
			local plot = Map.GetPlotByIndex(i)
			local tiles = GetCircle(i,1)
			local desertCount = 0
			local grassCount = 0
			for n=1,#tiles do
				local ii = tiles[n]
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetTerrainType() == terrainGrass then
					grassCount = grassCount + 1
				elseif nPlot:GetTerrainType() == terrainDesert then
					desertCount = desertCount + 1
				end
			end
			if desertCount >= 3 and grassCount == 0 then
				plot:SetTerrainType(terrainDesert,true,true)
				table.insert(g_DesertTab,i)
				table.remove(g_PlainsTab,k)
				if plot:GetFeatureType() ~= nofeature then
					plot:SetFeatureType(nofeature,-1)
				end
				k=k-1
			end
			k=k+1
		end
		-- Replaces stray Grass tiles -Bobert13
		k=1
		for n=1,#g_GrassTab do
			local i = g_GrassTab[k]
			local plot = Map.GetPlotByIndex(i)
			local tiles = GetCircle(i,1)
			local snowCount = 0
			local desertCount = 0
			local grassCount = 0
			for n=1,#tiles do
				local ii = tiles[n]
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if nPlot:GetTerrainType() == terrainGrass then
						grassCount = grassCount + 1
					elseif nPlot:GetTerrainType() == terrainDesert then
						desertCount = desertCount + 1
					elseif nPlot:GetTerrainType() == terrainSnow or nPlot:GetTerrainType() == terrainTundra  then
						snowCount = snowCount + 1
					end
				end
			end
			if desertCount >= 3 then
				plot:SetTerrainType(terrainDesert,true,true)
				table.insert(g_DesertTab,i)
				table.remove(g_GrassTab,k)
				if plot:GetFeatureType() ~= nofeature then
					plot:SetFeatureType(nofeature,-1)
				end
				k=k-1
			elseif snowCount >= 3 then
				plot:SetTerrainType(terrainPlains,true,true)
				table.insert(g_PlainsTab,i)
				table.remove(g_GrassTab,k)
				k=k-1
			elseif grassCount == 0 then
				if desertCount >= 2 then
					plot:SetTerrainType(terrainDesert,true,true)
					table.insert(g_DesertTab,i)
					table.remove(g_GrassTab,k)
					if plot:GetFeatureType() ~= nofeature then
						plot:SetFeatureType(nofeature,-1)
					end
					k=k-1
				elseif snowCount >= 2 then
					plot:SetTerrainType(terrainPlains,true,true)
					table.insert(g_PlainsTab,i)
					table.remove(g_GrassTab,k)
					k=k-1
				end
			end
			k=k+1
		end
		--Replaces stray Desert tiles with Plains or Grasslands. -Bobert13
		k=1
		for n=1,#g_DesertTab do
			local i = g_DesertTab[k]
			local plot = Map.GetPlotByIndex(i)
			local tiles = GetCircle(i,1)
			local snowCount = 0
			local desertCount = 0
			local grassCount = 0
			for n=1,#tiles do
				local ii = tiles[n]
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetTerrainType() == terrainGrass then
					grassCount = grassCount + 1
				elseif nPlot:GetTerrainType() == terrainDesert then
					desertCount = desertCount + 1
				elseif nPlot:GetTerrainType() == terrainSnow or nPlot:GetTerrainType() == terrainTundra  then
					snowCount = snowCount + 1
				end
			end
			if snowCount ~= 0 then
				plot:SetTerrainType(terrainPlains,true,true)
				table.insert(g_PlainsTab,i)
				table.remove(g_DesertTab,k)
				k=k-1
			elseif desertCount < 2 then
				if grassCount >= 4 then
					plot:SetTerrainType(terrainGrass,true,true)
					table.insert(g_GrassTab,i)
					table.remove(g_DesertTab,k)
					k=k-1
				elseif grassCount == 2 or grassCount == 3 or desertCount == 0 then
					plot:SetTerrainType(terrainPlains,true,true)
					table.insert(g_PlainsTab,i)
					table.remove(g_DesertTab,k)
					k=k-1
				end
			end
			k=k+1
		end
	end
	--Places marshes at river Deltas and in wet lowlands.
	local marshThreshold = g_ElevationMap:FindThresholdFromPercent(mc.marshElevation,false,true)
	for k = 1, #g_LandTab do
		local i = g_LandTab[k]
		local plot = Map.GetPlotByIndex(i)
		if not plot:IsMountain() then
			if g_TemperatureMap.data[i] > mc.treesMinTemperature then
				if plot:IsCoastalLand() then
					if plot:IsRiver() then
						if plot:GetTerrainType() ~= terrainDesert then
							local roll = PWRandInt(1,3)
							if roll == 1 then
								plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
								plot:SetTerrainType(terrainGrass, true, true)
								plot:SetFeatureType(featureMarsh,-1)
							end
						end
					end
				end
				if DiffMap.data[i] < marshThreshold then
					local tiles = GetCircle(i,1)
					local marsh = true
					for n=1,#tiles do
						local ii = tiles[n]
						local nPlot = Map.GetPlotByIndex(ii)
						if nPlot:GetTerrainType() == terrainDesert then
							if nPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
								marsh = false
							end								
						end
					end
					if marsh then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
						plot:SetTerrainType(terrainGrass, true, true)
						plot:SetFeatureType(featureMarsh,-1)
					end
				end
			end
			if plot:CanHaveFeature(featureFloodPlains) then
				plot:SetFeatureType(featureFloodPlains,-1)
			end
		end
	end
	Map.RecalculateAreas()
	PlacePossibleOasis()
end
------------------------------------------------------------------------------
function AddFeatures()
	PW_Log("Adding Features");
	local W, H = Map.GetGridSize()
	local WH = W*H

	local zeroTreesThreshold = g_RainfallMap:FindThresholdFromPercent(mc.zeroTreesPercent,false,true)
	local jungleThreshold = g_RainfallMap:FindThresholdFromPercent(mc.junglePercent,false,true)
	--local marshThreshold = g_RainfallMap:FindThresholdFromPercent(marshPercent,false,true)

	for i=0, WH-1, 1 do
		local plot = Map.GetPlotByIndex(i)
		if plot:IsWater() then
			PlacePossibleIce(i,W)
		elseif not plot:IsMountain() then
			-- plot is hills or flat land
			local x, y = g_TerrainTypesMap:DeprecatedGetIndexForDataIndex(i)
			local plot_type = g_PlotTypesMap:Get(x, y)
			local flat_terrain_type = g_TerrainTypesMap:Get(x, y)

			if plot:GetTerrainType() == g_TERRAIN_TYPE_DESERT then
				if plot:IsRiver() then
					TerrainBuilder.SetFeatureType(plot, g_FEATURE_FLOODPLAINS)
				else
					-- TODO: Place Oasis
				end
			elseif g_RainfallMap.data[i] >= jungleThreshold then -- Placing trees / marshes.
				if g_TemperatureMap.data[i] >= mc.jungleMinTemperature then
					TerrainBuilder.SetFeatureType(plot, g_FEATURE_JUNGLE)
					ApplyTerrainToPlot(plot, plot_type, g_TERRAIN_TYPE_PLAINS)
				elseif g_TemperatureMap.data[i] >= mc.treesMinTemperature then
					TerrainBuilder.SetFeatureType(plot, g_FEATURE_FOREST)
				end
			elseif g_RainfallMap.data[i] >= zeroTreesThreshold then
				-- There can be forests and marshes.
				-- local treeRange = jungleThreshold - zeroTreesThreshold
				if g_TemperatureMap.data[i] > mc.treesMinTemperature and
						PWRandInt(1, 100) <= 30 * g_RainfallMap.data[i] ^ 2 + 60 then
				--if g_TemperatureMap.data[i] > mc.treesMinTemperature and
				--		g_RainfallMap.data[i] > PWRand() * treeRange + zeroTreesThreshold then
					TerrainBuilder.SetFeatureType(plot, g_FEATURE_FOREST)
				elseif plot:GetTerrainType() == g_TERRAIN_TYPE_GRASS and
						PWRandInt(1, 100) <= 20 * g_RainfallMap.data[i] ^ 2 + 10 then
					TerrainBuilder.SetFeatureType(plot, g_FEATURE_MARSH)
				end
			end

			--if g_RainfallMap.data[i] < jungleThreshold then
			--	local treeRange = jungleThreshold - zeroTreesThreshold
			--	if g_RainfallMap.data[i] > PWRand() * treeRange + zeroTreesThreshold then
			--		if g_TemperatureMap.data[i] > mc.treesMinTemperature then
			--			TerrainBuilder.SetFeatureType(plot, g_FEATURE_FOREST)
			--		end
			--	end		
			--else
			--	if g_TemperatureMap.data[i] < mc.jungleMinTemperature and g_TemperatureMap.data[i] > mc.treesMinTemperature then
			--		TerrainBuilder.SetFeatureType(plot, g_FEATURE_FOREST)
			--	elseif g_TemperatureMap.data[i] >= mc.jungleMinTemperature then
			--		local tiles = GetCircle(i,1)
			--		local desertCount = 0
			--		for n=1,#tiles do
			--			local ii = tiles[n]
			--			local nPlot = Map.GetPlotByIndex(ii)
			--			if flat_terrain_type == g_TERRAIN_TYPE_DESERT then
			--				desertCount = desertCount + 1
			--			end
			--		end
			--		if desertCount < 4 then
			--			local roll = PWRandInt(1,100)
			--			if roll > 4 then
			--				TerrainBuilder.SetFeatureType(plot, g_FEATURE_JUNGLE)
			--				ApplyTerrainToPlot(plot, plot_type, g_TERRAIN_TYPE_PLAINS)
			--			else									
			--				TerrainBuilder.SetTerrainType(plot, flat_terrain_type);
			--				TerrainBuilder.SetFeatureType(plot, g_FEATURE_MARSH)
			--			end
			--		end
			--	end
			--end
		end
	end
end
-------------------------------------------------------------------------------------------
function AddRivers()
	local gridWidth, gridHeight = Map.GetGridSize();
	for y = 0, gridHeight - 1,1 do
		for x = 0,gridWidth - 1,1 do
			local plot = Map.GetPlot(x,y)
			local flat_terrain_type = g_TerrainTypesMap:Get(x,y)

			local WOfRiver, NWOfRiver, NEOfRiver = g_RiverMap:GetFlowDirections(x,y)

			if WOfRiver == FlowDirectionTypes.NO_FLOWDIRECTION then
				TerrainBuilder.SetWOfRiver(plot, false, WOfRiver);
			else
				local xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.E)
				local nPlot = Map.GetPlot(xx,yy)
				if plot:IsMountain() and nPlot:IsMountain() then
					TerrainBuilder.SetTerrainType(plot, flat_terrain_type);
				end
				TerrainBuilder.SetWOfRiver(plot, true, WOfRiver);
			end

			if NWOfRiver == FlowDirectionTypes.NO_FLOWDIRECTION then
				TerrainBuilder.SetNWOfRiver(plot, false, NWOfRiver);
			else
				local xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.SE)
				local nPlot = Map.GetPlot(xx,yy)
				if plot:IsMountain() and nPlot:IsMountain() then
					TerrainBuilder.SetTerrainType(plot, flat_terrain_type);
				end
				TerrainBuilder.SetNWOfRiver(plot, true, NWOfRiver);
			end

			if NEOfRiver == FlowDirectionTypes.NO_FLOWDIRECTION then
				TerrainBuilder.SetNEOfRiver(plot, false, NEOfRiver);
			else
				local xx,yy = g_ElevationMap:GetNeighbor(x,y,mc.SW)
				local nPlot = Map.GetPlot(xx,yy)
				if plot:IsMountain() and nPlot:IsMountain() then
					TerrainBuilder.SetTerrainType(plot, flat_terrain_type);
				end
				TerrainBuilder.SetNEOfRiver(plot, true, NEOfRiver);
			end
		end
	end
end
-------------------------------------------------------------------------------------------
--function StartPlotSystem()
--	-- Get Resources setting input by user.
--	local res = Map.GetCustomOption(2)
--	if res == 6 then
--		res = 1 + Map.Rand(3, "Random Resources Option - Lua");
--	end
--
--	local starts = Map.GetCustomOption(1)
--	local divMethod = nil
--	if starts == 1 then
--		divMethod = 2
--	else
--		divMethod = 1
--	end
--
--	print("Creating start plot database.");
--	local start_plot_database = AssignStartingPlots.Create()
--
--	print("Dividing the map in to Regions.");
--	-- Regional Division Method 2: Continental or 1:Terra
--	local args = {
--		method = divMethod,
--		resources = res,
--		};
--	start_plot_database:GenerateRegions(args)
--
--	print("Choosing start locations for civilizations.");
--	start_plot_database:ChooseLocations()
--
--	print("Normalizing start locations and assigning them to Players.");
--	start_plot_database:BalanceAndAssign()
--
--	--error(":P")
--	print("Placing Natural Wonders.");
--	start_plot_database:PlaceNaturalWonders()
--
--	print("Placing Resources and City States.");
--	start_plot_database:PlaceResourcesAndCityStates()
--end
-------------------------------------------------------------------------------------------
function oceanMatch(x,y)
	local plot = Map.GetPlot(x,y)
	if plot:GetPlotType() == PlotTypes.PLOT_OCEAN then
		return true
	end
	return false
end
-------------------------------------------------------------------------------------------
function jungleMatch(x,y)
	local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"];
	local plot = Map.GetPlot(x,y)
	if plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
		return true
	--include any mountains on the border as part of the desert.
	elseif (plot:GetFeatureType() == FeatureTypes.FEATURE_MARSH or plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST) and plot:GetTerrainType() == terrainGrass then
		local nList = g_ElevationMap:GetRadiusAroundHex(x,y,1,W)
		for n=1,#nList do
			local ii = nList[n]
			local xx = ii % W
			local yy = (ii - xx)/W
			if 11 ~= -1 then
				local nPlot = Map.GetPlot(xx,yy)
				if nPlot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
					return true
				end
			end
		end
	end
	return false
end
-------------------------------------------------------------------------------------------
function desertMatch(x,y)
	local W,H = Map.GetGridSize();
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
	local plot = Map.GetPlot(x,y)
	if plot:GetTerrainType() == terrainDesert then
		return true
	--include any mountains on the border as part of the desert.
	elseif plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		local nList = g_ElevationMap:GetRadiusAroundHex(x,y,1,W)
		for n=1,#nList do
			local ii = nList[n]
			local xx = ii % W
			local yy = (ii - xx)/W
			if 11 ~= -1 then
				local nPlot = Map.GetPlot(xx,yy)
				if nPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and nPlot:GetTerrainType() == terrainDesert then
					return true
				end
			end
		end
	end
	return false
end

-- #############################################################################
-- PerfectWorld 6 Types
-- #############################################################################

PW_RectMap = {}

function PW_RectMap:New(width, height, wrap_x, wrap_y, default_value)
	local obj = {}
	setmetatable(obj, {__index = self})

	obj.matrix_ = PW_Matrix:New(height, width, function() return default_value end)
	obj.width_ = width
	obj.height_ = height
	obj.default_value_ = default_value

	-- Choose the appropriate normalizing function on construction to avoid having
	-- to check whether to wrap or clamp on every call.
	local normalized_x = nil
	local normalized_y = nil

	if wrap_x then
		normalized_x = function(x) return WrapWithinClosedRange(x, 0, width - 1) end
	else
		normalized_x = function(x) return ClampToClosedRange(x, 0, width - 1) end
	end

	if wrap_y then
		normalized_y = function(y) return WrapWithinClosedRange(y, 0, height - 1) end
	else
		normalized_y = function(y) return ClampToClosedRange(y, 0, height - 1) end
	end

	-- TODO(omar): Remove this if it's not necessary.
	function obj.normalized_index_(x, y)
		return normalized_x(x), normalized_y(y)
	end

	function obj.matrix_index_(x, y)
		-- The row index (y) comes before the column index (x)
		return normalized_y(y), normalized_x(x)
	end

	return obj
end

function PW_RectMap:Height()
	return self.height_
end

function PW_RectMap:Width()
	return self.width_
end

function PW_RectMap:Get(x, y)
	local i, j = self.matrix_index_(x, y)
	return self.matrix_:Get(i, j)
end

function PW_RectMap:Reset(x, y, new_value)
	if new_value == nil then new_value = self.default_value_ end
	local i, j = self.matrix_index_(x, y)
	return self.matrix_:Reset(i, j, new_value)
end

function PW_RectMap:FillWith(fill_func)
	local function matrix_fill_func(x, y)
		return fill_func(y, x)
	end

	self.matrix_:FillWith(matrix_fill_func)
end

-------------------------------------------------------------------------------
-- PW_Matrix
-- A zero-based, potentially sparse, row-major matrix.
-------------------------------------------------------------------------------
PW_Matrix = {}

-- Returns a new matrix.
--
-- rows: the number of rows.
-- cols: the number of columns.
-- fill_func: an optional function, f(i, j), that supplies an initial value for
--            the matrix at row i, column j.
function PW_Matrix:New(rows, cols, fill_func)
	local obj = {}
	setmetatable(obj, {__index = self})

	obj.rows_ = rows
	obj.cols_ = cols
	obj.data_ = {}
	obj.index_ = function(i, j) return 1 + i * obj.rows_ + j end

	if fill_func then
		for i = 0, rows - 1 do
			for j = 0, cols - 1 do
				obj.data_[obj.index_(i, j)] = fill_func(i, j)
			end
		end
	end

	return obj
end

-- This should be easy to implement via PW_Matrix:New; just have fill_func
-- perform the copy.
-- function PW_Matrix:Clone()

function PW_Matrix:NumRows()
	return self.rows_
end

function PW_Matrix:NumCols()
	return self.cols_
end

function PW_Matrix:AcceptsIndex(i, j)
	return 0 <= i and i < self.rows_ and 0 <= j and j < self.cols_
end

function PW_Matrix:Get(i, j)
	assert(self:AcceptsIndex(i, j))
	return self.data_[self.index_(i, j)]
end

function PW_Matrix:Reset(i, j, value)
	assert(self:AcceptsIndex(i, j))
	self.data_[self.index_(i, j)] = value
end

function PW_Matrix:FillWith(fill_func)
	if not fill_func then return end
	for i = 0, self.rows_ - 1 do
		for j = 0, self.cols_ - 1 do
			self.data_[self.index_(i, j)] = fill_func(i, j)
		end
	end
end

--------------------------------------------------------------------------------

-- Tests for PW_Matrix
PW_Tests.MatrixTests = {}

function PW_Tests.MatrixTests.TestInitialization()
	local matrix = PW_Matrix:New(2, 3)
	if matrix:NumRows() ~= 2 then return PW_Status:Error("Wrong number of rows") end
	if matrix:NumCols() ~= 3 then return PW_Status:Error("Wrong number of columns") end

	if not matrix:AcceptsIndex(0, 0) then return PW_Status:Error("Zero based matrix does not accept (0, 0)") end
	if matrix:AcceptsIndex(2, 3) then return PW_Status:Error("Matrix has incorrect bounds") end

	for i = 0, matrix:NumRows() - 1 do
		for j = 0, matrix:NumCols() - 1 do
			if matrix:Get(i, j) ~= nil then return PW_Status:Error("Matrix not entirely empty") end
		end
	end

	function fill(i, j)
		return (i + 1) * (j + 1) ^ 2
	end

	matrix = PW_Matrix:New(3, 3, fill)
	for i = 0, matrix:NumRows() - 1 do
		for j = 0, matrix:NumCols() - 1 do
			if matrix:Get(i, j) ~= fill(i, j) then return PW_Status:Error("Matrix not filled properly") end
		end
	end
end

function PW_Tests.MatrixTests.TestFillWith()
	local matrix = PW_Matrix:New(3, 3)

	function fill(i, j)
		return (i + 1) * (j + 1) ^ 2
	end

	matrix:FillWith(fill)
	for i = 0, matrix:NumRows() - 1 do
		for j = 0, matrix:NumCols() - 1 do
			if matrix:Get(i, j) ~= fill(i, j) then return PW_Status:Error("Matrix not filled properly") end
		end
	end
end

function PW_Tests.MatrixTests.TestReset()
	local matrix = PW_Matrix:New(3, 3)
	
	if matrix:Get(0, 1) ~= nil then return PW_Status:Error("Value in matrix set unexpectedly") end
	
	matrix:Reset(0, 1, "apple")
	if matrix:Get(0, 1) ~= "apple" then return PW_Status:Error("Value in matrix not set to expected value") end
	
	matrix:Reset(0, 1, "banana")
	if matrix:Get(0, 1) ~= "banana" then return PW_Status:Error("Value in matrix not updated to expected value") end
	
	matrix:Reset(0, 1)
	if matrix:Get(0, 1) ~= nil then return PW_Status:Error("Value in matrix not erased") end
end

--------------------------------------------------------------------------------
-- Stuff to remove.
--------------------------------------------------------------------------------

function PW_RectMap:DeprecatedGetIndexForDataIndex(data_index)
	local i, j = self.matrix_:DeprecatedGetIndexForDataIndex(data_index)

	return j, i
end


function PW_Matrix:DeprecatedGetIndexForDataIndex(data_index)
	local j = data_index % self.cols_
	local i = (data_index - j) / self.cols_

	return i, j
end

-- #############################################################################
-- PerfectWorld 6 Math
-- #############################################################################

-- Tests for math functions.
PW_Tests.MathTests = {}

--------------------------------------------------------------------------------

-- Wraps a `value` to the closed interval [`min`, `max`].
function WrapWithinClosedRange(value, min, max)
	local shifted = value - min
	local limit = max - min + 1
	return shifted % limit + min
end

function PW_Tests.MathTests.TestWrapWithinClosedRange()
	if WrapWithinClosedRange(17, 0, 9) ~= 7 then return PW_Status:Error() end
	if WrapWithinClosedRange(-4, 0, 9) ~= 6 then return PW_Status:Error() end
	if WrapWithinClosedRange(14, 1, 12) ~= 2 then return PW_Status:Error() end
	if WrapWithinClosedRange(13, -8, 7) ~= -3 then return PW_Status:Error() end
end

--------------------------------------------------------------------------------

-- Clamps a `value` to the closed interval [`min`, `max`].
function ClampToClosedRange(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	else
		return value
	end
end

function PW_Tests.MathTests.TestClampToClosedRange()
	if ClampToClosedRange(-1, 0, 10) ~= 0 then return PW_Status:Error() end
	if ClampToClosedRange(11, 0, 10) ~= 10 then return PW_Status:Error() end
	if ClampToClosedRange("alligator", "b", "d") ~= "b" then return PW_Status:Error() end
	if ClampToClosedRange("dog", "b", "d") ~= "d" then return PW_Status:Error() end
end

-- #############################################################################
-- PerfectWorld 6 Errors
-- #############################################################################

PW_ERROR_CODE_NO_ERROR = 0
PW_ERROR_CODE_GENERIC_ERROR = 1
PW_ERROR_CODE_INTERNAL_ERROR = 2
PW_ERROR_CODE_NOT_IMPLEMENTED = 3
PW_ERROR_CODE_INVALID_ARGUMENT = 4
PW_ERROR_CODE_FAILED_PRECONDITION = 5
PW_ERROR_CODE_OUT_OF_RANGE = 6
PW_ERROR_CODE_NOT_FOUND = 7
PW_ERROR_CODE_ALREADY_EXISTS = 8

PW_Status = {}

function PW_Status:New(error_message, error_code)
	local obj = {}
	setmetatable(obj, {__index = self})

	obj.error_code = error_code
	obj.error_message = error_message

	return obj
end

function PW_Status:NoError()
	return self:New("", PW_ERROR_CODE_NO_ERROR)
end

function PW_Status:Error(error_message, error_code)
	error_message = error_message or ""
	error_code = error_code or PW_ERROR_CODE_GENERIC_ERROR
	return self:New(error_message, PW_ERROR_CODE_GENERIC_ERROR)
end

function PW_Status:is_error()
	return self.error_code ~= PW_ERROR_CODE_NO_ERROR
end

-- #############################################################################
-- PerfectWorld 6 Test Runner
-- #############################################################################

-- (omar): I did not want to embed a 3k line testing framework like LuaUnit.
--         We'll just have to use this very primitive test runner instead.

function PW_RunAllTests()
	PW_Log("Running Tests")

	local tests_run = 0
	local failed_tests = 0

	for suite_name, test_suite in pairs(PW_Tests) do
		for name, test in pairs(test_suite) do
			local status = test()
			local prefix = "[SUCCESS] "
			local suffix = ""
			if status and status:is_error() then
				prefix = "[FAILURE] "
				if status.error_message ~= "" then
					suffix = " -- " .. status.error_message
				end
				failed_tests = failed_tests + 1
			end

			PW_Log(prefix .. suite_name .. "." .. name .. suffix)
			tests_run = tests_run + 1
		end
	end

	PW_Log(tests_run .. " tests run; " .. failed_tests .. " failures")

	if failed_tests > 0 then error("Tests failed.") end
end
