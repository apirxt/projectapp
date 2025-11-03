module.exports = {
  root: true,
  env: {
    es2021: true,
    node: true,
  },
  extends: ["google"],
  rules: {
    quotes: ["error", "double"],
    "linebreak-style": 0,
    indent: 0,
    "comma-dangle": 0,
    "max-len": ["warn", { code: 120 }],
  },
};
