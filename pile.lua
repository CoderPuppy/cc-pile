--[=====[Pile of Packages by CoderPuppy]=====]
-- Combined module loader and package manager
-- Load it with shell.run

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
				error('No function passed to define(' .. module.id .. ')')
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

			setmetatable(env, { __index = _G })

			env = setmetatable({}, { __index = env })

			module.autoExport = true

			setfenv(fn, env)
			fn(unpack(deps))

			if module.autoExport and type(module.exports) == 'table' then
				setmetatable(module.exports, { __index = env })
			end

			module.loaded = true
			module.loading = false
		end,

		resolve = function(parent, name)
			local found = false
			local rtn = nil

			function tryPath(path)
				if pile.cache[path] or (fs.exists(path) and path:find('%.[^%.]+$')) then -- Load the file if the name has an extension
					rtn = path
					found = true

					return
				end

				for ext in pairs(pile.loaders) do
					if pile.cache[path .. '.' .. ext] or fs.exists(path .. '.' .. ext) then
						rtn = path .. '.' .. ext
						found = true

						return
					end
				end
			end

			-- Try the plain path first
			tryPath(name)

			if found then return rtn end

			if name[1] == '/' then -- Load from the root
				tryPath(fs.combine('/', name))
			elseif name:sub(1, 2) == './' then
				tryPath(fs.combine(shell.dir(), name))

				if found then return rtn end

				tryPath(fs.combine(fs.combine(parent.filename, '..'), name))
			else
				for i = 1, #pile.paths do
					tryPath(fs.combine(pile.paths[i], name))

					if found then return rtn end
				end

				local path = fs.combine(module.filename, '..')

				while #path > 0 do
					tryPath(fs.combine(fs.combine(path, '.pile'), name))

					if found then return rtn end

					path = fs.combine(path, '..')
				end
			end

			if found then return rtn end
		end,

		require = function(parent, file)
			if file == nil then return end -- Don't waste time with files that don't exist

			if pile.cache[file] == nil then
				pile.cache[file] = internal.createModule(parent, file)
				internal.loadModule(pile.cache[file])
			end

			return pile.cache[file]
		end,

		load = function(parent, file)
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
					local required = internal.require(module, internal.resolve(module, name))

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

			module.loading = true

			local ext = module.filename:match('%.([^%.]+)$')

			if pile.loaders[ext] == nil then
				module.loading = false
				error('Unknown extension: ' .. ext)
			else
				pile.loaders[ext](module)
			end

			return module
		end
	}

	internal.root = internal.createModule(nil, '/')
	internal.root.id = 'root'

	pile.cache = {} -- Modules that are already loaded
	pile.paths = {} -- Where to look for modules
	pile.require = internal.root.require
	pile.resolve = internal.root.resolve
	pile.loaders = { -- How to load a file
		lua = function(module)
			internal.define(module, true, {}, loadfile(module.filename))
		end
	}

	function pile.define(file, ...)
		file = fs.combine(internal.root.filename, file)

		if pile.cache[file] ~= nil then
			error('pile: module \'' .. file .. '\' is already loaded', 2)
		end

		local module = internal.createModule(internal.root, file)

		local ok, err = pcall(internal.define, module, ...)

		if not ok then
			error(err, 2)
		end

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

local tArgs = {...}

if tArgs[1] == 'init' then
	definePile(_G)
end