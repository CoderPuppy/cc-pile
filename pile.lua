--[=====[Pile of Packages by CoderPuppy]=====]
-- Module System
-- Load it with shell.run('pile.lua')
-- Reload it with shell.run('pile.lua init')

local function reerror(err, level)
	error(err:gsub('^pcall: ', ''), level == 0 and 0 or level + 1)
end

local function reerrorCall(level, fn, ...)
	local ok, rtn = pcall(fn, ...)

	if not ok then
		reerror(rtn, level == 0 and 0 or level + 1)
	end

	return rtn
end

local function definePile(_G)
	local pile = {}

	local internal
	internal = {
		define = function(module, ...)
			local fn
			local sugar = false
			local deps = { 'require', 'module', 'exports' }

			local args = {...}

			for i = 1, #args do
				local arg = args[i]

				if type(arg) == 'function' then
					fn = arg
				elseif type(arg) == 'boolean' then
					sugar = arg
				elseif type(arg) == 'table' then
					deps = arg
				end
			end

			if type(fn) ~= 'function' then
				error('No function passed to define(' .. module.id .. ')', 2)
			end

			for i = 1, #deps do
				deps[i] = module.require(deps[i])
			end

			local env = {
				shell = shell -- Because shell isn't in _G
			}

			if sugar then
				env.module = module
				env.require = module.require
				env.exports = module.exports

				-- This doesn't work
				-- setmetatable(env, { __index = function(t, k)
				-- 	if k == 'module' then
				-- 		return module
				-- 	elseif k == 'exports' then
				-- 		return module.exports
				-- 	elseif k == 'require' then
				-- 		return module.require
				-- 	else
				-- 		return rawget(t, k)
				-- 	end
				-- end })
			end

			setmetatable(env, {
				__index = _G,
				__newindex = function(t, k, v)
					if module.autoExport then
						module.exports[k] = v
					end

					rawset(env, k, v)
				end
			})

			-- TODO: Is there any way i could autodetect when to turn this off
			module.autoExport = true

			setfenv(fn, env)

			module.loading = true

			local ok, err = pcall(function() return fn(unpack(deps)) end)

			module.loading = false

			if ok then
				module.loaded = true
			else
				reerror(module.filename .. ': ' .. err:gsub('^pcall: ', ''), 2)
			end
		end,

		resolve = function(parent, name)
			local found = false
			local rtn = nil

			function resolveFile(path)
				if pile.cache[path] or (fs.exists(path) and (not fs.isDir(path)) and path:find('%.[^%./]+$')) then -- Load the file if the name has an extension
					rtn = path
					found = true

					return true
				end

				for ext in pairs(pile.loaders) do
					if pile.cache[path .. '.' .. ext] or fs.exists(path .. '.' .. ext) then
						rtn = path .. '.' .. ext
						found = true

						return true
					end
				end
			end

			function resolveDir(path)
				local packagePath = fs.combine(path, 'pile-package.lua')
				if fs.exists(packagePath) and not fs.isDir(packagePath) then
					local f = fs.open(packagePath, 'r')

					local package = pile.parsePackage(f.readAll())

					f.close()

					if type(package) == 'table' and type(package.main) == 'string' and resolveFile(fs.combine(path, package.main)) then return true end
				end

				if resolveFile(fs.combine(path, 'index')) then return true end
			end

			function tryPath(path)
				if resolveFile(path) then return true end
				if resolveDir(path) then return true end
			end

			-- Try the plain path first
			tryPath(fs.combine('/', name))
			if found then return rtn end

			if name[1] == '/' then -- Load from the root
				tryPath(fs.combine('/', name))
				if found then return rtn end
			end

			if name:sub(1, 2) == './' or name:sub(1, 3) == '../' then
				tryPath(fs.combine(shell.dir(), name))
				if found then return rtn end

				tryPath(fs.combine(fs.combine(parent.filename, '..'), name))
				if found then return rtn end
			end

			if name == '.' then
				tryPath(shell.dir())
				if found then return rtn end

				tryPath(fs.combine(parent.filename, '..'))
				if found then return rtn end
			end

			if name == '..' then
				tryPath(fs.combine(shell.dir(), '..'))
				if found then return rtn end

				tryPath(fs.combine(parent.filename, '../..'))
				if found then return rtn end
			end

			for i = 1, #pile.paths do
				tryPath(fs.combine(pile.paths[i], name))
				if found then return rtn end
			end

			local path = fs.combine(parent.filename, '.')

			if #path ~= 0 then
				path = fs.combine(path, '..')
			end

			repeat
				tryPath(fs.combine(fs.combine(path, '.pile'), name))

				if found then return rtn end

				path = fs.combine(path, '..')
			until path --[[:sub(1, 2)]] == '..'
		end,

		require = function(parent, file)
			if file == nil then
				error('No such file/module: ' .. file, 2)
			end

			if pile.cache[file] == nil then
				pile.cache[file] = internal.createModule(parent, file)
				reerrorCall(3, internal.loadModule, pile.cache[file])
			end

			return pile.cache[file]
		end,

		load = function(parent, file)
			if file == nil then
				error('No such file/module: ' .. file, 2)
			end

			return internal.loadModule(internal.createModule(parent, file))
		end,

		createModule = function(parent, file)
			local module
			module = {
				id = file:gsub('%.[^%.]+$', ''),
				filename = file,
				loaded = false,
				loading = false,
				parent = parent,
				children = {},
				exports = {},
				resolve = function(name)
					return internal.resolve(module, name)
				end
			}

			local function require(name)
				if name == 'require' then
					return module.require
				elseif name == 'module' then
					return module
				elseif name == 'exports' then
					return module.exports
				else
					local file = internal.resolve(module, name)

					if type(file) ~= 'string' then error('No such file/module: ' .. name, 3) end

					local required = internal.require(module, file)

					if required ~= nil then
						return required.exports
					end
				end
			end

			module.require = setmetatable({}, {
				__call = function(t, ...) return require(...) end,
				__index = function(t, k)
					if k == 'paths' then return pile.paths
					elseif k == 'cache' then return pile.cache
					elseif k == 'loaders' then return pile.loaders
					elseif k == 'resolve' then return module.resolve
					else return rawget(t, k) end
				end
			})

			if type(parent) == 'table' then
				parent.children[#parent.children + 1] = module
			end

			return module
		end,

		loadModule = function(module)
			if module.loading then
				print('Warning: ' .. module.id .. ' is already being loaded')
				print('You probably have a circular dependency')
				return module
			end

			local ext = module.filename:match('%.([^%.]+)$')

			if pile.loaders[ext] == nil then
				module.loading = false
				error('Unknown extension: ' .. ext)
			else
				reerrorCall(0, pile.loaders[ext], module)
			end

			return module
		end
	}

	internal.root = internal.createModule(nil, '/')
	internal.root.id = 'root'

	pile.internal = internal

	pile.cache = {} -- Modules that are already loaded
	pile.paths = {} -- Where to look for modules
	pile.require = internal.root.require
	pile.resolve = internal.root.resolve
	pile.loaders = { -- How to load a file
		lua = function(module)
			local fn, err = loadfile(module.filename)
			if type(fn) ~= 'function' then
				module.loading = false
				error(err)
			end
			reerrorCall(0, internal.define, module, true, {}, fn)
		end
	}

	pile.pile = pile

	function pile.define(file, ...)
		file = fs.combine(internal.root.filename, file)

		if pile.cache[file] ~= nil then
			error('pile: module \'' .. file .. '\' is already loaded', 2)
		end

		local module = internal.createModule(internal.root, file)

		reerrorCall(1, internal.define, module, ...)

		pile.cache[module.id] = module

		return module
	end

	setmetatable(pile, {
		__call = function(t, ...) return pile.require(...) end
	})

	_G.pile = pile
	_G.require = pile
	_G.define = pile.define
end

if _G.pile == nil then
	definePile(_G)
end

local args = {}

for i, arg in ipairs({...}) do
	if arg:sub(1, 2) == '--' then
		local arg = arg:sub(3)
		local match = {arg:match('^([^=]+)=(.*)$')}
		if match then
			local name = match[1]
			local val = match[2]
			args[name] = val
		elseif arg:sub(1, 3) == 'no-' then
			args[arg:sub(4)] = false
		else
			args[arg] = true
		end
	elseif arg:sub(1, 1) == '-' then
		for flag in arg:sub(2):gmatch('.') do
			args[flag] = true
		end
	else
		args[#args + 1] = arg
	end
end

if args[1] == 'init' then
	definePile(_G)
elseif args[1] == 'install' or args[1] == 'i' then
	local pkgs = {}
	for i, arg in ipairs(args) do

	end
end