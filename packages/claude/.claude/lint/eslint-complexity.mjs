import tsParser from "@typescript-eslint/parser";

// 複雑度のみを見る共有設定。対象リポジトリの ESLint 設定とは独立に、
// post-edit-check.sh が編集ファイル1件に対して当てる。閾値は golangci-complexity.yml と揃える。
const complexityRules = {
  complexity: ["warn", 20],
  "max-depth": ["warn", 4],
  "max-lines-per-function": [
    "warn",
    { max: 60, skipComments: true, skipBlankLines: true },
  ],
  "max-nested-callbacks": ["warn", 4],
};

const languageOptions = {
  ecmaVersion: "latest",
  sourceType: "module",
  parserOptions: { ecmaFeatures: { jsx: true } },
};

export default [
  {
    files: ["**/*.js", "**/*.mjs", "**/*.cjs", "**/*.jsx"],
    languageOptions,
    rules: complexityRules,
  },
  {
    files: ["**/*.ts", "**/*.tsx", "**/*.mts", "**/*.cts"],
    languageOptions: { ...languageOptions, parser: tsParser },
    rules: complexityRules,
  },
  {
    // テストは記述が長く、コールバックも深くなるのが正常
    files: [
      "**/*.test.*",
      "**/*.spec.*",
      "**/__tests__/**",
      "**/test/**",
      "**/tests/**",
    ],
    rules: {
      "max-lines-per-function": "off",
      "max-nested-callbacks": "off",
    },
  },
];
