module.exports = {
  root: true,
  env: {
    es2021: true,
    node: true,
  },
  extends: ["google"],
  rules: {
  // ผ่อนกฎสไตล์ให้เข้ากับโค้ดในโปรเจกต์นี้
  quotes: 0, // อนุญาตทั้งเครื่องหมาย ' และ "
    "linebreak-style": 0,
    indent: 0,
    "comma-dangle": 0,
    "max-len": 0,
    "object-curly-spacing": ["error", "always"],
    "block-spacing": ["error", "always"],
    "brace-style": ["error", "1tbs", { allowSingleLine: true }],
    "quote-props": "off",
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
    "arrow-parens": ["error", "always"],
  },
};
