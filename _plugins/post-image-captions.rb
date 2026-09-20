# frozen_string_literal: true

require "cgi"

# Turns standard Markdown image links in posts into semantic figures. The
# Markdown alt text becomes the visible caption, so writeups keep using the
# normal ![caption](image) syntax without requiring per-image HTML.
Jekyll::Hooks.register :posts, :post_render do |post|
  post.output.gsub!(
    %r{<p>\s*(?<link><a\b[^>]*\bclass="[^"]*\bimg-link\b[^"]*"[^>]*>\s*<img\b[^>]*\balt="(?<alt>[^"]+)"[^>]*>\s*</a>)\s*</p>}im
  ) do
    caption = CGI.escapeHTML(CGI.unescapeHTML(Regexp.last_match[:alt]))
    %(<figure class="rn-evidence">#{Regexp.last_match[:link]}<figcaption>#{caption}</figcaption></figure>)
  end
end
