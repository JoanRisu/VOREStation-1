/*
Asset cache quick users guide:

Make a datum at the bottom of this file with your assets for your thing.
The simple subsystem will most like be of use for most cases.
Then call get_asset_datum() with the type of the datum you created and store the return
Then call .send(client) on that stored return value.

You can set verify to TRUE if you want send() to sleep until the client has the assets.
*/


// Amount of time(ds) MAX to send per asset, if this get exceeded we cancel the sleeping.
// This is doubled for the first asset, then added per asset after
#define ASSET_CACHE_SEND_TIMEOUT 7

//When sending mutiple assets, how many before we give the client a quaint little sending resources message
#define ASSET_CACHE_TELL_CLIENT_AMOUNT 8

//When passively preloading assets, how many to send at once? Too high creates noticable lag where as too low can flood the client's cache with "verify" files
#define ASSET_CACHE_PRELOAD_CONCURRENT 3

/client
	var/list/cache = list() // List of all assets sent to this client by the asset cache.
	var/list/completed_asset_jobs = list() // List of all completed jobs, awaiting acknowledgement.
	var/list/sending = list()
	var/last_asset_job = 0 // Last job done.

//This proc sends the asset to the client, but only if it needs it.
//This proc blocks(sleeps) unless verify is set to false
/proc/send_asset(var/client/client, var/asset_name, var/verify = TRUE)
	client = CLIENT_FROM_VAR(client) // Will get client from a mob, or accept a client, or return null
	if(!istype(client))
		return 0

	if(client.cache.Find(asset_name) || client.sending.Find(asset_name))
		return 0

	client << browse_rsc(SSassets.cache[asset_name], asset_name)
	if(!verify) // Can't access the asset cache browser, rip.
		client.cache += asset_name
		return 1

	client.sending |= asset_name
	var/job = ++client.last_asset_job

	client << browse({"
	<script>
		window.location.href="?asset_cache_confirm_arrival=[job]"
	</script>
	"}, "window=asset_cache_browser")

	var/t = 0
	var/timeout_time = (ASSET_CACHE_SEND_TIMEOUT * client.sending.len) + ASSET_CACHE_SEND_TIMEOUT
	while(client && !client.completed_asset_jobs.Find(job) && t < timeout_time) // Reception is handled in Topic()
		sleep(1) // Lock up the caller until this is received.
		t++

	if(client)
		client.sending -= asset_name
		client.cache |= asset_name
		client.completed_asset_jobs -= job

	return 1

//This proc blocks(sleeps) unless verify is set to false
/proc/send_asset_list(var/client/client, var/list/asset_list, var/verify = TRUE)
	client = CLIENT_FROM_VAR(client) // Will get client from a mob, or accept a client, or return null
	if(!istype(client))
		return 0

	var/list/unreceived = asset_list - (client.cache + client.sending)
	if(!unreceived || !unreceived.len)
		return 0
	if(unreceived.len >= ASSET_CACHE_TELL_CLIENT_AMOUNT)
		to_chat(client, "Sending Resources...")
	for(var/asset in unreceived)
		if(asset in SSassets.cache)
			client << browse_rsc(SSassets.cache[asset], asset)

	if(!verify) // Can't access the asset cache browser, rip.
		client.cache += unreceived
		return 1

	client.sending |= unreceived
	var/job = ++client.last_asset_job

	client << browse({"
	<script>
		window.location.href="?asset_cache_confirm_arrival=[job]"
	</script>
	"}, "window=asset_cache_browser")

	var/t = 0
	var/timeout_time = ASSET_CACHE_SEND_TIMEOUT * client.sending.len
	while(client && !client.completed_asset_jobs.Find(job) && t < timeout_time) // Reception is handled in Topic()
		sleep(1) // Lock up the caller until this is received.
		t++

	if(client)
		client.sending -= unreceived
		client.cache |= unreceived
		client.completed_asset_jobs -= job

	return 1

//This proc will download the files without clogging up the browse() queue, used for passively sending files on connection start.
//The proc calls procs that sleep for long times.
/proc/getFilesSlow(var/client/client, var/list/files, var/register_asset = TRUE)
	var/concurrent_tracker = 1
	for(var/file in files)
		if(!client)
			break
		if(register_asset)
			register_asset(file, files[file])
		if(concurrent_tracker >= ASSET_CACHE_PRELOAD_CONCURRENT)
			concurrent_tracker = 1
			send_asset(client, file)
		else
			concurrent_tracker++
			send_asset(client, file, verify = FALSE)
		sleep(0) //queuing calls like this too quickly can cause issues in some client versions

//This proc "registers" an asset, it adds it to the cache for further use, you cannot touch it from this point on or you'll fuck things up.
//if it's an icon or something be careful, you'll have to copy it before further use.
/proc/register_asset(var/asset_name, var/asset)
	SSassets.cache[asset_name] = asset

//These datums are used to populate the asset cache, the proc "register()" does this.

//all of our asset datums, used for referring to these later
/var/global/list/asset_datums = list()

//get a assetdatum or make a new one
/proc/get_asset_datum(var/type)
	if(!(type in asset_datums))
		return new type()
	return asset_datums[type]

/datum/asset
	var/_abstract = /datum/asset // Marker so we don't instanatiate abstract types

/datum/asset/New()
	asset_datums[type] = src
	register()

/datum/asset/proc/register()
	return

/datum/asset/proc/send(client)
	return

//If you don't need anything complicated.
/datum/asset/simple
	_abstract = /datum/asset/simple
	var/assets = list()
	var/verify = FALSE

/datum/asset/simple/register()
	for(var/asset_name in assets)
		register_asset(asset_name, assets[asset_name])
/datum/asset/simple/send(client)
	send_asset_list(client,assets,verify)

//
// iconsheet Assets - For making lots of icon states available at once without sending a thousand tiny files.
//
/datum/asset/iconsheet
	_abstract = /datum/asset/iconsheet
	var/name // Name of the iconsheet. Asset will be named after this.
	var/verify = FALSE

/datum/asset/iconsheet/register(var/list/sprites)
	if (!name)
		CRASH("iconsheet [type] cannot register without a name")
	if (!islist(sprites))
		CRASH("iconsheet [type] cannot register without a sprites list")

	var/res_name = "iconsheet_[name].css"
	var/fname = "data/iconsheets/[res_name]"
	fdel(fname)
	text2file(generate_css(sprites), fname)
	register_asset(res_name, fcopy_rsc(fname))
	fdel(fname)

/datum/asset/iconsheet/send(client/C)
	if (!name)
		return
	send_asset_list(C, list("iconsheet_[name].css"), verify)

/datum/asset/iconsheet/proc/generate_css(var/list/sprites)
	var/list/out = list(".[name]{display:inline-block;}")
	for(var/sprite_id in sprites)
		var/icon/I = sprites[sprite_id]
		var/data_url = "'data:image/png;base64,[icon2base64(I)]'"
		out += ".[name].[sprite_id]{width:[I.Width()]px;height:[I.Height()]px;background-image:url([data_url]);}"
	return out.Join("\n")

/datum/asset/iconsheet/proc/build_sprite_list(icon/I, list/directions, prefix = null)
	if (length(prefix))
		prefix = "[prefix]-"

	if (!directions)
		directions = list(SOUTH)

	var/sprites = list()
	for (var/icon_state_name in cached_icon_states(I))
		for (var/direction in directions)
			var/suffix = (directions.len > 1) ? "-[dir2text(direction)]" : ""
			var/sprite_name = "[prefix][icon_state_name][suffix]"
			var/icon/sprite = icon(I, icon_state=icon_state_name, dir=direction, frame=1, moving=FALSE)
			if (!sprite || !length(cached_icon_states(sprite)))  // that direction or state doesn't exist
				continue
			sprites[sprite_name] = sprite
	return sprites

// Get HTML link tag for including the iconsheet css file.
/datum/asset/iconsheet/proc/css_tag()
	return "<link rel='stylesheet' href='iconsheet_[name].css' />"

// get HTML tag for showing an icon
/datum/asset/iconsheet/proc/icon_tag(icon_state, dir = SOUTH)
	return "<span class='[name] [icon_state]-[dir2text(dir)]'></span>"

//DEFINITIONS FOR ASSET DATUMS START HERE.
/datum/asset/simple/generic
	assets = list(
		"search.js" = 'html/search.js',
		"panels.css" = 'html/panels.css',
		"loading.gif" = 'html/images/loading.gif',
		"ntlogo.png" = 'html/images/ntlogo.png',
		"sglogo.png" = 'html/images/sglogo.png',
		"talisman.png" = 'html/images/talisman.png',
		"paper_bg.png" = 'html/images/paper_bg.png',
		"no_image32.png" = 'html/images/no_image32.png',
	)
	
/datum/asset/simple/changelog
	assets = list(
		"88x31.png" = 'html/88x31.png',
		"bug-minus.png" = 'html/bug-minus.png',
		"cross-circle.png" = 'html/cross-circle.png',
		"hard-hat-exclamation.png" = 'html/hard-hat-exclamation.png',
		"image-minus.png" = 'html/image-minus.png',
		"image-plus.png" = 'html/image-plus.png',
		"map-pencil.png" = 'html/map-pencil.png',
		"music-minus.png" = 'html/music-minus.png',
		"music-plus.png" = 'html/music-plus.png',
		"tick-circle.png" = 'html/tick-circle.png',
		"wrench-screwdriver.png" = 'html/wrench-screwdriver.png',
		"spell-check.png" = 'html/spell-check.png',
		"burn-exclamation.png" = 'html/burn-exclamation.png',
		"chevron.png" = 'html/chevron.png',
		"chevron-expand.png" = 'html/chevron-expand.png',
		"changelog.css" = 'html/changelog.css',
		"changelog.js" = 'html/changelog.js',
		"changelog.html" = 'html/changelog.html'
	)

/datum/asset/nanoui
	var/list/common = list()

	var/list/common_dirs = list(
		"nano/css/",
		"nano/images/",
		"nano/images/modular_computers/",
		"nano/js/"
	)
	var/list/template_dirs = list(
		"nano/templates/"
	)

/datum/asset/nanoui/register()
	// Crawl the directories to find files.
	for(var/path in common_dirs)
		var/list/filenames = flist(path)
		for(var/filename in filenames)
			if(copytext(filename, length(filename)) != "/") // Ignore directories.
				if(fexists(path + filename))
					common[filename] = fcopy_rsc(path + filename)
					register_asset(filename, common[filename])
	// Combine all templates into a single bundle.
	var/list/template_data = list()
	for(var/path in template_dirs)
		var/list/filenames = flist(path)
		for(var/filename in filenames)
			if(copytext(filename, length(filename) - 4) == ".tmpl") // Ignore directories.
				template_data[filename] = file2text(path + filename)
	var/template_bundle = "function nanouiTemplateBundle(){return [json_encode(template_data)];}"
	var/fname = "data/nano_templates_bundle.js"
	fdel(fname)
	text2file(template_bundle, fname)
	register_asset("nano_templates_bundle.js", fcopy_rsc(fname))
	fdel(fname)

/datum/asset/nanoui/send(client)
	send_asset_list(client, common)


// VOREStation Add Start - pipes iconsheet asset
/datum/asset/iconsheet/pipes
	name = "pipes"

/datum/asset/iconsheet/pipes/register()
	var/list/sprites = list()
	for (var/each in list('icons/obj/pipe-item.dmi', 'icons/obj/pipes/disposal.dmi'))
		sprites += build_sprite_list(each, global.alldirs)
	..(sprites)
// VOREStation Add End
