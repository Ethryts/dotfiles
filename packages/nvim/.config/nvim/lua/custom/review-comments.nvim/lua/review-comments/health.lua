-- `:checkhealth` resolves the literal plugin name as a Lua module. Keep the
-- public command spelling aligned with the plugin name while the main Lua API
-- continues to use the conventional `review_comments` module.
return require('review_comments.health')
