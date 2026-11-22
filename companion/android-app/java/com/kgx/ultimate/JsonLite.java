package com.kgx.ultimate;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class JsonLite {
    private final String src;
    private int pos;

    private JsonLite(String src) {
        this.src = src != null ? src : "";
    }

    public static Object parse(String text) {
        if (text == null) return null;
        String trimmed = text.trim();
        if (trimmed.isEmpty()) return null;
        return new JsonLite(trimmed).readValue();
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> asMap(Object obj) {
        if (obj instanceof Map) return (Map<String, Object>) obj;
        return new LinkedHashMap<>();
    }

    @SuppressWarnings("unchecked")
    public static List<Object> asList(Object obj) {
        if (obj instanceof List) return (List<Object>) obj;
        return new ArrayList<>();
    }

    public static String str(Map<String, Object> m, String key, String def) {
        if (m == null) return def;
        Object v = m.get(key);
        return v == null ? def : String.valueOf(v);
    }

    public static boolean bool(Map<String, Object> m, String key, boolean def) {
        if (m == null) return def;
        Object v = m.get(key);
        if (v instanceof Boolean) return (Boolean) v;
        if (v instanceof Number) return ((Number) v).intValue() != 0;
        if (v instanceof String) {
            String s = (String) v;
            return "true".equalsIgnoreCase(s) || "1".equals(s);
        }
        return def;
    }

    public static long num(Map<String, Object> m, String key, long def) {
        if (m == null) return def;
        Object v = m.get(key);
        if (v instanceof Number) return ((Number) v).longValue();
        if (v instanceof String) {
            try { return Long.parseLong((String) v); } catch (Exception ignored) {}
        }
        return def;
    }

    private void skipWs() {
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if (c == ' ' || c == '\n' || c == '\r' || c == '\t') pos++;
            else break;
        }
    }

    private Object readValue() {
        skipWs();
        if (pos >= src.length()) return null;
        char c = src.charAt(pos);
        if (c == '{') return readObject();
        if (c == '[') return readArray();
        if (c == '"') return readString();
        if (c == 't' && src.startsWith("true", pos)) { pos += 4; return Boolean.TRUE; }
        if (c == 'f' && src.startsWith("false", pos)) { pos += 5; return Boolean.FALSE; }
        if (c == 'n' && src.startsWith("null", pos)) { pos += 4; return null; }
        return readNumber();
    }

    private Map<String, Object> readObject() {
        Map<String, Object> map = new LinkedHashMap<>();
        pos++; // '{'
        skipWs();
        if (pos < src.length() && src.charAt(pos) == '}') {
            pos++;
            return map;
        }
        while (pos < src.length()) {
            skipWs();
            if (pos >= src.length() || src.charAt(pos) != '"') break;
            String key = readString();
            skipWs();
            if (pos < src.length() && src.charAt(pos) == ':') pos++;
            Object val = readValue();
            map.put(key, val);
            skipWs();
            if (pos < src.length() && src.charAt(pos) == ',') {
                pos++;
            } else {
                if (pos < src.length() && src.charAt(pos) == '}') pos++;
                break;
            }
        }
        return map;
    }

    private List<Object> readArray() {
        List<Object> list = new ArrayList<>();
        pos++; // '['
        skipWs();
        if (pos < src.length() && src.charAt(pos) == ']') {
            pos++;
            return list;
        }
        while (pos < src.length()) {
            list.add(readValue());
            skipWs();
            if (pos < src.length() && src.charAt(pos) == ',') {
                pos++;
            } else {
                if (pos < src.length() && src.charAt(pos) == ']') pos++;
                break;
            }
        }
        return list;
    }

    private String readString() {
        StringBuilder sb = new StringBuilder();
        pos++; // opening quote
        while (pos < src.length()) {
            char c = src.charAt(pos++);
            if (c == '"') break;
            if (c == '\\' && pos < src.length()) {
                char esc = src.charAt(pos++);
                switch (esc) {
                    case '"': sb.append('"'); break;
                    case '\\': sb.append('\\'); break;
                    case '/': sb.append('/'); break;
                    case 'b': sb.append('\b'); break;
                    case 'f': sb.append('\f'); break;
                    case 'n': sb.append('\n'); break;
                    case 'r': sb.append('\r'); break;
                    case 't': sb.append('\t'); break;
                    case 'u':
                        if (pos + 4 <= src.length()) {
                            try {
                                sb.append((char) Integer.parseInt(src.substring(pos, pos + 4), 16));
                            } catch (Exception ignored) {}
                            pos += 4;
                        }
                        break;
                    default: sb.append(esc); break;
                }
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    private Object readNumber() {
        int start = pos;
        boolean isFloat = false;
        while (pos < src.length()) {
            char c = src.charAt(pos);
            if ((c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') {
                if (c == '.' || c == 'e' || c == 'E') isFloat = true;
                pos++;
            } else {
                break;
            }
        }
        String token = src.substring(start, pos);
        try {
            if (isFloat) return Double.parseDouble(token);
            return Long.parseLong(token);
        } catch (Exception e) {
            return 0L;
        }
    }
}
