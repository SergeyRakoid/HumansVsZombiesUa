module.exports = (role) ->
	(req, res, next) ->
		userRole = req.user?.role
		res.viewData = res.viewData or {}
		res.viewData.isAuth = req.isAuthenticated()
		res.viewData.user = req.user
		if res.viewData.isAuth and role is 'any'
			return next()
		if userRole is 'admin' or role is undefined
			return next()
		if userRole isnt role
			return res.redirect '/'
		next()