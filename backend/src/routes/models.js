const express = require('express');
const { listModels, getDefaultModel } = require('../utils/modelCatalog');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const [models, defaultModel] = await Promise.all([
      listModels(),
      getDefaultModel(),
    ]);
    res.json({ models, default_model: defaultModel });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch models' });
  }
});

module.exports = router;
