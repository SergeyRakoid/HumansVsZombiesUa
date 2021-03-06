express = require('express')
http = require('http')
passport = require('passport')
cookieParser = require('cookie-parser')
bodyParser = require('body-parser')
session = require('express-session')
expressWinston = require('express-winston')
log = require('winston-wrapper')(module)
winston = require('winston')
config = require('cnf')
bootable = require 'bootable'
favicon = require('serve-favicon')
mongoose = require 'mongoose'
authorize = require './middleware/authorizeRole'
moment = require 'moment'
uuid = require 'node-uuid'
async = require 'async'
MongoStore = require('connect-mongo')(session)
UserFactory = require './modules/userFactory'

app = bootable(express())
server = http.createServer(app)

app.use(favicon(__dirname + '/client/img/favicon.png'))
app.set('views', __dirname + '/views')
app.set('view engine', 'jade')
app.use(express.static(__dirname + '/client'))
app.use(cookieParser(config.cookieSecret))
app.use(bodyParser())
app.use session
	secret: config.sessionSecret
	store: new MongoStore url: config.mongoUrl
	maxAge: 3600 * 24 * 2
app.use(passport.initialize())
app.use(passport.session())

app.phase(bootable.initializers('setup/initializers/'))

app.all '/', (req, res, next) ->
	res.header("Access-Control-Allow-Origin", "*")
	res.header("Access-Control-Allow-Headers", "X-Requested-With")
	next()

app.get '/', authorize(), (req, res) ->
	User = mongoose.model('user')
	start = moment(config.startDate, "YYYY-MM-DD HH-mm")
	end = moment(config.endDate, "YYYY-MM-DD HH-mm")
	res.viewData.toStart = start.diff(moment())
	res.viewData.toEnd = end.diff(moment())
	res.viewData.hasStarted = start.diff(moment()) < 0
	res.viewData.hasEnded = end.diff(moment) < 0
	User.find (err, users) ->
		res.viewData.section = 'home'
		res.viewData.users = users
		res.render('home', res.viewData)

app.get '/admin', authorize('admin'),
(req, res, next) ->
	User = mongoose.model 'user'
	Medicine = mongoose.model 'medicine'
	User.find (err, users) ->
		if err then return next(err)
		users = users.reduce (list, user) ->
			list.push UserFactory(user.toObject()).getInfo()
			list
		, []
		res.viewData.users = users
		Medicine.find (err, medicines) ->
			if err then return next(err)
			res.viewData.medicines = medicines
			res.viewData.section = 'admin'
			res.render 'admin', res.viewData

app.post '/admin/generatemedcine', authorize('admin'), (req, res, next) ->
	count = parseInt(req.body.count) || 0
	unless 0 < count < 101
		return next(new Error("Сірьожа, '#{count}' не канає, не більше 100, не менше 1"))
	Medicine = mongoose.model 'medicine'
	createCode = (cb) ->
		medicine = new Medicine
			code: uuid.v4().substr(0, 13)
			generated: new Date()
		medicine.save cb

	async.times count, (n, next) ->
		createCode(next)
	, (err, codes) ->
		if err
			return next(err)
		console.log("generated #{codes.length} medicine codes")
		res.redirect '/admin'

app.post '/human/submitMedicine', authorize('human'), (req, res, next) ->
	code = req.body.code
	Medicine = mongoose.model 'medicine'
	User = mongoose.model 'user'
	if !code then return next(new Error 'Code should be provided')
	Medicine.findOneAndUpdate {'code': code, 'usedBy': { $exists: no }, generated: {}}, {usedBy: req.user.vkontakteId, usedTime: new Date()}, (err, data) ->
		if err then return next(err)
		if data
			User.findOneAndUpdate { 'vkontakteId': req.user.vkontakteId }, { lastActionDate: new Date() }, (err, data) ->
				if err then return next(err)
				res.viewData.profileMessage = "Код сработал"
				res.render('profile', res.viewData)
		else
			res.viewData.profileMessage = "Извините, код не работает. Истек срок придатности или код уже использован"
			res.render('profile', res.viewData)

app.post '/zombie/submitHuman', authorize('zombie'), (req, res, next) ->
	hash = req.body.hash
	User = mongoose.model 'user'
	if !hash then return next(new Error 'Hash should be provided')
	User.findOne {'hash': hash}, (err, user) ->
		if err then return next(err)
		if user
			userObj = user.toObject()
			UserFactory(userObj).getInfo()
			if userObj.role isnt 'human' or userObj.isDead
				res.viewData.profileMessage = "Нельзя сьесть зомби или труп"
				return res.render('profile', res.viewData)
			user.getZombie = new Date()
			user.lastActionDate = new Date()
			user.save (err) ->
				if err then return next(err)
				User.findOne { 'vkontakteId': req.user.vkontakteId }, (err, thisUser) ->
					if err then return next(err)
					thisUser.lastActionDate =  new Date()
					if !thisUser.getZombie
						thisUser.getZombie = new Date()
					thisUser.save (err, user) ->
						if err then return next(err)
						res.viewData.user = UserFactory(user.toObject()).getInfo()
						res.viewData.profileMessage = "Код сработал"
						res.render('profile', res.viewData)
		else
			res.viewData.profileMessage = "Извините, человек не найден"
			res.render('profile', res.viewData)

app.get '/auth/vkontakte',
	passport.authenticate('vkontakte', { scope: ['friends'] }),
	(req, res) ->
		res.redirect('/')

app.get '/auth/vkontakte/callback',
	passport.authenticate('vkontakte', { failureRedirect: '/' }),
	(req, res) ->
		res.redirect('/')

app.get '/logout', (req, res) ->
	req.logout()
	res.redirect('/')

app.get '/teamHuman', authorize('human'), (req, res) ->
	res.viewData.title = 'Команда зомби'
	res.viewData.vkAppId = config.vk.appId
	res.viewData.section = 'teamHuman'
	User = mongoose.model('user')
	User.find (err, users) ->
		teamUsers = []
		for user in users
			user = UserFactory(user).getInfo()
			if user.role is 'human'
				teamUsers.push user
		res.viewData.users = teamUsers
		res.render('teamHuman', res.viewData)

app.get '/teamZombie', authorize('zombie'), (req, res) ->
	res.viewData.title = 'Команда людей'
	res.viewData.vkAppId = config.vk.appId
	res.viewData.section = 'teamZombie'
	User = mongoose.model('user')
	User.find (err, users) ->
		teamUsers = []
		for user in users
			user = UserFactory(user).getInfo()
			if user.role is 'zombie'
				teamUsers.push user
		res.viewData.users = teamUsers
		res.render('teamZombie', res.viewData)

app.get '/profile', authorize('any'), (req, res) ->
	res.render('profile', res.viewData)

app.get '/rules', authorize(), (req, res) ->
	res.viewData.section = 'rules'
	res.render('rules', res.viewData)

app.use (req, res) ->
	authorize()(req, res, ->
		res.status(404).render('404', res.viewData)
	);

app.use expressWinston.errorLogger
	transports: [
		new winston.transports.Console({
			colorize: true
		})
	]

app.use (err, req, res, next) ->
	authorize()(req, res, ->
		res.viewData.message = err;
		res.status(500).render('500', res.viewData)
	);

app.boot (err) ->
	if err
		console.error err
	port = config.http.port
	server.listen port
	console.info('server started at ' + config.http.siteUrl + ' '.green)
