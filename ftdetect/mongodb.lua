-- Detect *.mongo.js up front so the filetype isn't briefly javascript, which
-- would attach javascript LSP clients that then stay attached.
vim.filetype.add({ pattern = { ['.*%.mongo%.js'] = 'mongodb' } })
