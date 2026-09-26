if not CLIENT then return end
hook.Remove("Think", "ZCChatReactionVisibilityRepair")
local previous = ZCChatMedia
if previous and previous.Close then previous.Close() end
local M = {Version = "20260923.settings2", Emojis = {}, Order = {}, Thumbs = {}, Rows = setmetatable({}, {__mode = "k"})}
ZCChatMedia = M
if not ZCChatThreads or ZCChatThreads.Version ~= "20260923.settings2" then include("zc_chat_media/threads.lua") end
if not ZCChatGroupUI or ZCChatGroupUI.Version ~= "20260923.groups1a" then include("zc_chat_media/groups.lua") end
local gifs = CreateClientConVar("zc_chat_gifs", "1", true, false, "Automatically show GIFs in chat", 0, 1)
local videos = CreateClientConVar("zc_chat_videos", "1", true, false, "Show video players in chat", 0, 1)
local inlineMedia = CreateClientConVar("zc_chat_inline_media", "1", true, false, "Show inline media and media links in chat", 0, 1)
local videoVolume = CreateClientConVar("zc_chat_video_volume", "40", true, false, "Chat video volume", 0, 100)
local emojiData = {
{name="smile",sha="ae89e05450587e8f1f4786c0d266cf94ef2b306782fb6f9c30e43c0023ed148b",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAh1BMVEVHcEz/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3GmTCMZxNmRQDisz+DXg5wTQX1xEh5VgqziSfZqjrsu0OWbxjPojWfeB2pgCK8kSvs6N/Z0b+zooCWf1CDaDB5XCD18+/////i3M+8ro+MdECfi2BwURDGuZ/Pxa9Pcc+sAAAADnRSTlMAIGCPv9//UJ/vQK+Az1vcyGwAAAJDSURBVHgBpNPVoUQhDATQyWUZEqT/cp+uC5bzD3F0yBFOkWfxFA7BhqSRL6ImLJFg/MCCYFYu7CoZM0Q5pIKhapxgFX3SOKkJOpJxmqVOWVxS8YFykfr/OVP/P2fa6Y+zT4mbEh6IcZMJ7jVua/4GndVOYbvFKV0UZ5lOGf8Kncq5Q3QT/Ap0C/hldLPzcfgl9+zPFEAk/aJ/ZmeCg2c+xzfzZaEfPQgE8c+lEgaP27m8//M1v/NbstTl354FGBx2Ric/ERgQSfw5WQC/gmdS4YCS/HPCr3CspcYJLfnndLRZHVIieE6gQkbhCmviz1khB4KLP2eFNADh/A4nAOj4c15IO3PRUac1/5wKvZwvLvT7bXR+B1tE+icUMz4NtsjPcD3azOUpp5HmLrMAhCGb9voYKXBCidJVfke6e69cKRROFOQYuT7Y8AzIwXY12ualQr93hz8Rqpu268Ey6dqmpkL/6HWEgX46G5g3i7Zd7uiXe9p20cxnA9OeCv2lF6TFwGr2CCsMWHpBXi2AAsc28Uz7YNZ+BkFEjh3rhtdp1tiRkyCChDUWe7p6XKbusMeSsIYGWgmOLDfToFObJY4kNNCioZ/CmWW7nR9F5tt2iTOKzH0YjEo8CTkead+FnYuTcC7ini6BOAUN2GnnnqhUsBaCbBSHKI5uDt5m5RosOqf+IWb8TAaGzDzTQnqBEYR/gamVhSadKiRvRON21DthscMK559s1x9G8QAC5UMalA+yUD7sQ8+BKMJDY3QZrKN8+BAAXe+ec4BPStgAAAAASUVORK5CYII="},
{name="laugh",sha="c252a58367211c11d839155e50dc5e98551826c64b8d2e8d6267124c054ceae0",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAwFBMVEVHcExdrexdrexdrez/zE3+zE7/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE1drez/zE1drezbxXBdreyziSj/zE1mRQD1xEiMZxNwTQXsu0PZqjryylqku6bisz////92stOMdECfeB3GmTBkrOGDXg6+u46WbxhlVCK8kSuzooCuvZ2pgCJghZDPojXi3M/Z0b/Lv6fMwn/cxXCCiG+aubDx7ueo0/WJxPJ5Vw6DaDCWf1BeoM9ieXZic2dfmsB8zBAYAAAAE3RSTlMAgM8Y349QIJ/vv2BAr8+PgHCPJC8E5gAAAyNJREFUeF6tmNd2ozAQQAkGG1yS7KrQXXsv6WV3//+vNpaFByRLxj7chzxM8GVmNFJiGRpqDbtuEY5Vtxs14waqjkUkLKd6naVmu0SBaxfPq9kiWlrNYtk45CJOgaweXVIA9/FSOvekIPfapKouKYxb1ZRFrkJZnkOuxCnBA6YSPGBS9+f2PlXJjQhrV3NvFbn5eSo8h54nTaamQeFyRCk+58GUjpah0CZVYZFPGUTGoww/koqTVz6cUKoRcSbhuRloEmAWUIayNE4wI0CTi1oQ6qdvHHiKZg/SjPsQbPEOwVMj/kxINIT8bSN417FLtuAZtckF2iPBZDORm68LkwIs89W5uc0xY54BKcSAmWawUWDtQ/AUN4WZCbC4yNfUpZwEnwcsWLMI4peBN0endWtAGDItRJhNqZEuvpddhQGz+tAvKQ6rfBqAekYUwpQIEyXGISU+S3XDgt7hoyegJwIwiXH4DO+2cGSBRzCJcfGYAxFskywfnj6uFOE/07wJp5XnmP7FetF+iIbUxxED+4ciCCOgNBv/eWyvEy3QD2MIeDhIRQH2xOfUohd0oEsu0kUHXiQReBhPlzx7hCSTIXtQohLAk7LJsKDulG6xynJ9stItQsYIiPWeJ4QkU92w5V+iZ7wOVZZwjZ9RCjTU5sdIPMyKVmxn+ks8ixgh+znDS5/N9yorGsb8GKmdqga+qRZ4KXS0djxqE5RH65miPIvjUWs40CBo0qfa8wEtgjY57M9R3BVFb53OZjuez3uMz96R+Xy83XQ6b6KoGx//b3MXSBZpeEciC9c48BtJvF8nGtpMdIdktmrPFsn8YiITydCv1/Oa1y+KZEwmYgF5/Xs7yfW661HKRCIHT0UhOrjmu00q2ezmPRij4iINKpFRhkjV7H860beq2Q+yaKUTrWTRnaFo0lS/aSUqxvmUknWg9gTrRE6IY0qb0JuoPBNP2uSmkVIxBQ98IwHgW4hgMnlhYnUJ4bT7QoFBv02OxIlQF1B5MFk2SUwyRNj/4MeZjyMe5CqWlflQKfMCofwrjfIvWYpf+5R1EVX+1Vj5l3WlXR/+B3ehafKkDafjAAAAAElFTkSuQmCC"},
{name="skull",sha="9fd5d570065aa68949bb713242f3915938d5bbaf7e24fe319b0553214c63e085",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAKlBMVEVHcEzM1t3M1t3M1t3M1t3M19vM1d3M1t3M1t0pLzM/RUqXoKZ0fIFhaG35YWMYAAAACHRSTlMAZ8ztjBgzrj8n7f8AAAGdSURBVHja7ZfBjusgDEWxHcCQ9P9/9y3a0ZXi1A7xLN5iziISMjrC3EDa4tFo6yyiKsJ9o1aeUIlFTwhTXdQQ6xeYVhYj6iB3VdCkVLXrDXpdWE5qUaS32TzPppozwZM2wZM3kS5Dl7mLLiOtWFgfwMnGAOUaA1JziYHNWVBmSaRgf80x5mtX4NXoS2T7HB+mUZmaCa7pD8cY4IDDqbUCNjsXs6PadtHZPk6gg6ua7U0/zHFiqsY1u0X7MOwa15oJ/zUML41rZPZ6DsPUuIbd7vpmXKBxrSO0nAixSa41gSi32RBpLn6FKPVCWtH6EbGixKE1ouVrBJjU1i82G/+zq9aKUkDEmoJ/X9Q1RTf3UfpjS5qC7GftOvExkPcVrYT544jtbvrxbuNYHM5eA3I8oYlKiXubEE2nM0CPRFgQYKe14/10X+vwDTjmPN7PIPv8r1oDJT2gSe6HP6ir/45q+UbrepveikfVm9QSoDcpK6LOqoD7Y9F59Cf6X0WCueKOIhiT2R1FECaTO7q/JHZHMZU/c2swiiEWYXJHln+a9XQyB9XeaAAAAABJRU5ErkJggg=="},
{name="cry",sha="c22c89c24607d04f39094af2216b611d1d033055b31afafbc6a185990982b844",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAtFBMVEVHcEz/zE3/zE1drez/zE3/zE3/zE3/zE3/zE3/zE1drexdrez/zE3/zE3/zE1drez/zE1drexdrexdrexdrexdrey3vpRdrexmRQD/zE2Wbxj1xEiziSddreypgCJwTQXGmTDsu0N5VgqfeB2MZxPZqjqDXg68kSvPojXisz/nWnCGShyWTSrfWWlieXa/U01gjaKuvZ1hgIVfk7FghpRkXztic2dep93XxHXMwn9jZkplTA/sGJLAAAAAGHRSTlMA379AgFCPnyDvgM9Ar8+fYL9Q348Qj++69LDZAAACt0lEQVR4Xt2X13qjMBBG6cUVp45ExzW1bC/v/16LbRIxjCUw4WrPZX6+E82MEkmaAi9wDJ1V6IYTeFoPbFdnBN21z7N4js8k+E73dU2mTMl00m01LmvF7bAqy2cd8K225cxYR2bKRdk+64xvK8piZyEtz2Vn4g7hoSbq6W+i/enfJ5v1pDE7z+8r8vF+mrHezFoaFAFEsp9hLGVhGZQ0RVCSqYpzT3uoCJnoHphIPElTlEhMk0o0bQZb2LNhhM0h2DaDadUhhgn50RNSUXg08WZ07JKDPeuCeIipWOPAOYjQyPIl0F9KlwvLHA2u+ccRRimQPp/sOKRRvT4bzT5PKk26YwrW718lOdoButi3FcuQKQmr8mv7XK/NLKzC1Zq1sl5VplDMLcD7tshYJ7ICi4La8COymtZVRbUNYIgo3PvvtslqBVCseIStNAtDERnHXou5FVAjXeZtmeg2/n9DiNSZAImAAspMLfr+4/nb1y8RT9Fcqr2R7LPnP3+rTNAsjb/+jA+U2Y7j0viutMZHXjktDRNXMIQq//9F+jAiXTOGERma0yaKCoAiahM5WiAR4XMDNqFaFGieVCQ8wiRyeiDpKlECHyQqkY4Ofiq6gxp3KKfHv60QcajBcU7vbb5UlAMil4p8dGRT0RYQW5TTI9uTijjAw8v9gZcHAC4VeehaQ0UpPN5/8AipTDTFFy0qAngSoicAmWhCrn5EdF8DID8tcslltE3UzOlN2/pMaRa5sBPRBjd7c1I0I08IKsrw+DOUi8IQNhWVLKHGEuf4UYPbRD/M+Pv1jGc4lz9H3R6niOoJ2V2kftR2FwkPxTpPZGkyzJvfb3FH3n7dmERwbY6uFuO4B+PF1ci8Plou5pfxJ7mcX2jaOB6E8WCioUobrNkY0zRHo9F8UXIrE9zu03n52YWJxv8P3/K8svS3naMAAAAASUVORK5CYII="},
{name="angry",sha="f65d755195cfb95f5c3e38a33d5ccd935236ff2869a720cdbcb8ac667c073e7e",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAV1BMVEVHcEzaL0faL0faL0faL0faL0faL0faL0faL0faL0faL0faL0faL0faL0eCLz0pLzNKLzdVLziuL0LPL0ajL0FgLzmYL0BrLzvEL0V2Lzw0LzS5L0M/LzaqdrzsAAAADnRSTlMAIGCPv9//UJ/vQK+Az1vcyGwAAAH1SURBVHgBpNNFogAgCATQwRjBuP9xf3dYvL3SmJAQU+abnGIQXCia+UvWgiMSjf+wKNhVG6daxQ5RLqlgqRs3WMecDG4agoli3GZlUhaPdPxDeUhn//h/Ul7QSX+cfSq8VPCNGC+Z4KvBa8PfoDf9trBJcUoXxZtKp4pXjU4NL4RugmeRbhHPjG7mOo7HVsxwN2EYBsJaR8N+ILuNE1JC3/85hyZKuFJulfD305quc2yci585Qu0/7IA+ONA71GypWxcaojeGUaIFgiUZB70hodFB8fVBPtsblXPWB9AABxRqlCm8MBVtgNABzloUKBYAuyggcNr4pzEmyVXv1BSeSC2eJcXVQYLQwjXjR/HfzdcAECGrunBZYi2taruFRBsbhZDdQgMXGv4XIl8XbewVMn1gEP1AaKJREOppajwKDXlghz3wKPxEvln5hUZxanekIauxKNBtD7akfyQaBb7ejNo0q86JRoHebfi7XUdeF6Tble1oIritiTIuzTNKJLaGGi2TWYFZjBst7ACc9UhNm7WnZrToJoU77RPX4UonZthF3yLMsK+Tm5bJUyTekTK0+YiJAcfXxMa1kbDz+JrckT6zVDVPYYMprybtiT/8KtQZSLX6PyHdHrU/Xs91rwWC10rDacnitfbxWkT5r8b8l3Vu68Nf9kV7PrX8SsAAAAAASUVORK5CYII="},
{name="think",sha="5116f7d07677f06785887c0af23c189b541a306d6b792d605ffaf3ed9f0e912d",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAvVBMVEVHcEz/y0z/y0z/y0z/y0z/y0z/y0z/y0z/y0z/y0z/y0z/y0zxkCDxkCD/y0z/y0zxkCDxkCDxkCD/y0z/y0zzliTxkCDxkCDxkCD7uT7xkCDxkCDxkCDxkCDxkCDxkCD/y0yyiTTxkCCMaCdlRxuCYCTFmjr8wETylCOfeS31w0n9xEe8kTf1oi54WCHsu0b4rjZvTx73pzHiskP7uT6VcCr6tTz1nSn5sTn+x0n8vEHPoj3ZqkCogTDzlyZJUBfDAAAAIHRSTlMAUCDfYO+AEM+/j59Az68wEJ8wQHBQv98gz49g769wgLdoNu0AAALWSURBVHhezZjZVqNAEIYxITREjTpus08v7GTdF5f3f6whodEORbUNxwu/S49+p/7qKmi0NJBbZ+BRiTdwbonVgs6dSwHuXaehxvYogmc30XSphq6p6gxogOrMQEMG1IAB+bCcHjWi90FRfWpMXxfrvBAsmBj7B8ar4QQ1nRPUU0zOcOyrBE+YySVaT+hXWTQ0yVysCCVeGFsFR9Eznk7X5zTwg7fOpKHwg7RRx89oK8AUdHrtRL3qFnu0JV6LYJOh7P5MsAUSDuxpmuQndzpBia8yZqncYNXjAE9x8KEq8ivMZFWOriAmf1c9+VkpEKIwrUBJNq2SbwkoacFY4Q8ofTrkTGiBbZW4IJkvYaeBZ+8/nbBhWa5bejq0yjMUqWs4pqd0YKtL6kWs9FdEDkxWEkjRk5FIZiMUEoIMOhEl+FQnclLwHsHVdWgdoRDJBJmKsCpyTPYVnqZANtel5ixWs0CeJOw2/QS+poh8HREeLZouP0W05Jy/Rp8gGvGcuJGpfiDn/MDmOMohyxk+p3qPW78ia35kqdwn5Fscw6tf2qwQzanwVRJc5SCPkUIU08Q/5UV/A+ggIr5Lh3l7DjCBmtSHtouI9oo7Pd7jBNJr5AYaQVFOytBsfSm6gscPRTmTSbasnfkr9QUJC+KVOrfz1+NhIsnAKzuKpWf0LtlPRzEvyWgJeGWTnvI30lMm2y3nG2lAEvdI3bVmzUu2eZp1ngaQwWmEJUX8DZkGMMUKUruUxVxLPNpqOqRs7objvM7XGbKv4Hq8xyQbIIHXYzXcCK1G0cBg8FOEo4yafIx4EcfBH2gQ8kPT6UYfbBe4aKrxQL41a5FHLAx8ECOkzwiXqGkO5se2NPw0zuaBOTRs0haUo+cBW5ETjQO6bDoA8U79Xw2xDLjRj1G3f2WZcX2Jibpe3wYdbmy6t5pzDdP9/mW14uJRtTz++fvdasvFTRHw4d+9seQ/xqXp+/TYvsUAAAAASUVORK5CYII="},
{name="heart",sha="68da7c6dc7d9c0456174f2575abe8f8abd52cde7a4017700579519173a8a4a34",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAM1BMVEVHcEzdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkTdLkQVM82yAAAAEHRSTlMAIN+fzzBAEO+/j3Bgr1CAS8Xz9AAAAV5JREFUeF7l2M2OgzAMhdGbEOK4/N33f9rRMMISamgF9m7O1tKnNgmtAv6Vsdbx4dykSRt3bZlSb74cc7X5u7nwRFecrMqTMqOnZr7RClOVb7LNjbzY9To6V3PBiRReKPJ9bjA2Xipina42wkjmB0Ws05UFh8KPloUflaOz0WnDLtEt4ZfSTQFgZIARwMAAA4DGAA2oDFGxMcSGhSEWKEMoCkMUMAgaQ7SwNQoLxZ2jlSFWJIZIUQ9t5M/IzAAzAGEAAYCFbgt+rXRbsct0yvgzByz1ThpdGg4TXSaY7Fwhs3q3zKjzf9+kxodawsnkXWmj7i/mOkxN8KbygYqOjbdt6Bp404A+KbylCC5Idne+XyX6Vwd/yTrXJXfHSu6OlZwdI8WxXyei/Eh7nQdnfMANc+OFNuOWsbCrjLhJXhe38/tqvnpf4P1QL8FTSWk0waOqvSXxqgM5VEQQwb/2A80o0l7lU88FAAAAAElFTkSuQmCC"},
{name="fire",sha="b0f4c358afcce0ddcde029e72ea2d6054eece0ce5a34c9a7e0c5761ff4f33a25",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAh1BMVEVHcEz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz0kAz/zE3/zE3/zE3/zE3/zE3/zE3/zE3/zE39wkL/zE3/zE3/zE3/zE30kAz/zE36ri33nxz+yEn+xUX5qij8vT32mxj9wUH3oyD1mBT6sjH1lBD7tjX8uTmQeifTAAAAHXRSTlMAMEBQv++PEM+A359gryBwzxDvv4CPUK9gIN9gMOUtXcUAAAKrSURBVHjarZfZkoIwEEWDLEkAcXfWDpu78//fN4OMqdAkJFCeJy3LI919OwJxJAtm5DUkENGXiGYAof8SUwwAERkPxV+K4I+AjvawoFdbAxtrYpAQBDiacB1c06SG+RiPBxpRAC2cuDMHgMQkgszZkz2a0W/bP4GzaAENuKsg8dwra0hJBx8kiXuIG2K8bJLQVaQbjwcKM3cRLo7KVlsTEGX9ti56Hnso/Vg3H5bSRsNDkFgCkIUJEklXwAATm0UBcPWNDaMn7UwimiyicUfkTxZxtIoxaLEnMkQ/YqstMHUIb6I/UcRw7Gegw7q1nkyxq2jR/b7X6UjiXBpeWj9SK4OQujcbzZz9h6i30jSEQRg+B2mnjtBzXZE5Pgd9mcbW1JbuMbDA8aw4/n3GOceao21oi2euLBdwqvLb4NDiZ9NgmFqIMscinDkX0VH8cToaSwtcRVA2pvJs2JCFDFYGFg7iQXtNOLteKEUULNxbUXlBlyQ9rqXlouWgFkcf18ABJohEAQoB5/MQpokOYEQfSJS/H/HkMrzFAW5uAR0qKaqHj14OHa7ijAIp+RneYh9UzkLkaPqSExjwSS9IlxI19SgUwMB/QBnu7E1p/Ela0Aeo1+iELkRDjj2aJBXK6+iZc+NeFYoHieqD5i6XqRfUUNa3pu93gcjV4Rb9/4JUM6GqFH2uarrumlvNUB49w1Sdc1Nza8JlZRZqNRRF/z+FxnI9nUy10rGYEoVUzsxGlefXSj0NUs0zVCVGUelulbKm32IkTaczgvCniXzSI5oiioiG+XjR3PCoP1ZkenSny3GeJSUGVm9jPG8rYmbn7tmRQfZrN816Tyx8bFw8mw9i5/3Tpvl8J06stuvBqraUOPO1NM78i4zje7fUWHbfZAKr/XazlI7Ndj8UnF+YwEpCshNBaAAAAABJRU5ErkJggg=="},
{name="thumbsup",sha="42b43325b3edacba2a0e72b742bdc6fc5e4bc2ad38adca271fcc6d8353639887",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAk1BMVEVHcEz/217/217/217/217/217/217/217/217/217/217/217ulUf/217/217ulUfulUf/217ulUf/217ulUf3uFP4v1X7zFnwnEnzqU78zVnulUfvm0nwn0rulUfulUf/217ulUf7ylj3uFP0r1Dzq07+1138zlr5wVXwnkrvmUjxokvyp036xVf1tFH4vFT90lstgPVGAAAAIHRSTlMAcGDfIBCfQL+Az6/v7zAQMFDfj4CAUN+fcO9Qv99gcEnxpdkAAAIGSURBVHherZbZkpswEEUFFiC8zTj7nsu6eJ3//7oA5VQUpLbVJZ1HHk5JfbtbCIokzlUaSeFLssNM7iuKcCf1FCn8JQ8lggwl2oQSQYYSRaFEKpQIwUSJh2gNjcxDBJ29x6ghUI0yaOz8Z9Y//hQa7z1EK4TpbIlA6cehQttAYxWqi1Sg8LEJlBnWXm2to/I7cTYj+SuERqk8etYWBzijIvnwjeWQSsqzBo9dbC/0ChRlPRQ6V9yxmGQKkrpYUhLDmMRrcDxFpw2RcRiKyyw461TW/RDjMadR07RkdEYzk4yeY0snZzxjFOUoqkFj7A2KbroZVb6qhPPNMKdEHvYzISLSP/alSXUcRR/dRW/Hgmb74i5C/8DzKoKITt8kQ9TOV2sqkwugGKLbqBneQCDdRc0ouoAidhedRxFIcp7IfrOuqdvIXVRNpaZSaPaMhpzXkdnatynNn5w+uhY03zkinEjPb0GIeMM2fBWUiF7+dbXk1kGxRO3k6WFFEiL2rj1wRRXd1/4n6s9Nd+DXyP4oSP/U5o8/RJg+2r7yROjspu0vwRS1VlH9Sejs4Vika/k/7fJ3Hs+ZDlRa+1pnA/7rb/4b8VubFonIZUUO5gI+dguRyNIVHjKYQ9JP102ESZY+Wf/FcNaYd+YXYWW/Zu7a7Yuwk9D5tRbTO30+3IvVnxaaD//O8wc9hoFwgKeolwAAAABJRU5ErkJggg=="},
{name="clap",sha="876e139116fc16aa3c4d125fc455be61e9c68bf474539ca822a2d2edee6a7459",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAwFBMVEVHcEzvlkX6dD76dD7vlkX6dD7vlkX6dD7/217/217/2176dD76dD7vlkX6dD7vlkXvlkX6dD7/217vlkX6dD75v1Tzi0LvlkXvlkXvlkX6dD76dD7/2176dD7vlkX/217/2176dD7/217/217vlkX/217vlkX/2176dD7/217/217/217vlkX4u1Lzp0vzqEz/217vlkX6dD7+11zwmkf1sE73uFH6wlXyo0r8zlnzp0v7yljxn0j4vVP0rE390ltJgxsEAAAAMHRSTlMAMBDP7zAQn+8wQCBgYN8gn4+fr+9gUIC/j79Av4BwzxCvcN/Pj0CAcK9gIN/vv+9vRgWIAAAC70lEQVR4Xq3XaXeiMBSA4UsUsIKgo3VdapfpMp0lCYt7+///1cQEjNiQI7Hvdx5Nzr1yBJPQmAY2fEOvlNJ7CXgatDnF+O29DAoKUIdSt9TBhxo3asemLD93XMr6elCnP7cAHrFO6lAWko4KsuqEkOEtxjpJnEw6iqOFzGFtsE4SJ9M60CabzY6QGOukGXN6SOvA3zUDtjFJddKEP6t1Fg0OrGOyVEmLnw08bQLMxi7il65ywnkrhJ8Ya6TFHYd/5S5SOQPCGk2xWrr9TcjQEh8jJaRwWoS3xWopWhFC6g18JrlfHKgLKMU6KXek5HlQzCJZa520LEjKnByKddIGl0jIv3dtIQ2V0upMSrDsAfL6fJqCkxWL2VQXpKgg4aQg/RCM36MiuaxJxIB9XE3yaFYNculfdp5qki2YYIaA5Tw/O3CHjaQxpb2ODbzW4YJGGJtJkwlkPRNeZCjJngS0xNdKRLSLrpVI1upSaV+QXiCvW1larxLVtoT1i6QtPmm5Vv2CWpdIKS7tDipI2uQCO4cRSNJ0ZyY1FieSeGZvJj2AlLInlkbSY/4mGlhNzhhLN8c3yB9cKn1qCTmVfXLoA5dJKb6gqdzZ6EyqVkOu2ge+SpLvRpJcJTUBRuQ7pKaYanNJQgaSGjKT1BA4XbW0rAKJ2koJV4ek9BFJyQSSU7Aykh7gWOsq6RG+S3pRS+ZfaTIRLwFzCVi226O0dqUEqBNQnn2VNIUazfKAFT6ZSY0byJieDzzHQOIOBAfF7TPDRJIOeK7rIzjJGSolvaOuLSUjx/OMJOko/jRJycRheefrsvo0ciiCcynemjgdYCF3PGNSPx/yNKrsuEfTZ5KVD1TMKAMH9Rg04+SgTrKSZVTVAV8sMC9sHymyStL9toID98wJ5Ji3usISxUlU7tgFB+WXLrP6g8HoeGF7tSMg6ciTnRfmN7bj9/Wm2C9XfAV5shooc7J5r1vwDspsDwrQK5QUzrvD4dyBS7IDOkZg0H+ZU5/r/tqnmQAAAABJRU5ErkJggg=="},
{name="poop",sha="91f689597621d1bed4653fb69281128d46ac44cca08248e4cef1ef7f9a46b724",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAqFBMVEVHcEy/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVK/aVLCcl3hwrvy7/D1+PrJhHLGe2fo1NDNjXzP0tVcYWUpLzPc3+E2PD/u5uV2en6aW0qHU0Y8NjdbTlWObXfAjJjZnKnyq7phRT82Nzvlo7JrSEEyMzWjXkzAg4fSgnnso63ilprCbVnPfnPcjo3lm6Dvp7TGenEzWXW+AAAAEXRSTlMAgP9An+8wUHAQj9/PIL9gr22nQ4wAAAJQSURBVHgBrdeHbvJAEATg9djn3n64VHqH9J73f7MfWSwIfDYb7E99iEbsNQU6x4JNbXAA5bbTAyiPmvJRgBNQI4HCjgrdxl+IRaEX0IVinIj9y7pQctkW2jBQSUtFcOjPPJgo+hPbShXMSCzIctRIxBMp1CKhDPWUkzXYqmPKCiSnWSKy6QwXQpnsnjZvsiClkpaKkAquhUwieRT/dbpadzv/wAxZKJjtqqsL3SuwchZTjSTE1nVX73SvUTBmNTUOCjd67waozM4eolu9dXff693faX3L2T7hrLLIwU5Ha90f9LYGfd3hbJ9ozsgsBBtqrUe9wkgPOdsnepdFZ0+Q3hr0CgOtOTsknOUBGUTHRb2dQ9Eh4QyRW/ueyYugyk05/jQai0rTgYkX23x1EzDp9rPM/FTLDySLKovkV8T4lcDEl5blFcdI/oywigsif9iYXd62y1jHRVErRUEItFHkxmilyFVowmqpBz6vT4R2inI0lZn/sxr3RManRzLFiUlPZIKDKDCe6GlPYHq6cRZKxvLJmOLJKoebzRfLVWG5mM/Kg7GMYLLuFTbzh9WRh/mmV1jjhEMweuxtcc1xVW/rEacigtnkabNYGS02TxOUESo8v6wqvDxDVsRe31YGb6+AvIir3lcn3ks1jFLU+fj8+v5ZFX6+v34/UIkstCImF60I+Wg35fIz0lDU9GFjHv9qaCht5/GHCqiVJuUSc6OmPSxwUCH1XbIdhUppQEfsHCWpZe8/tlKYRB6VJH4e8cepY3lu6Q9sy0rTGHtx6BL7D7OFc9+QTZ5eAAAAAElFTkSuQmCC"},
{name="eyes",sha="487739c941203283fc25b1bac02b4b8f3d59672e3dec2154f575060206bbb86a",data="iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAMAAABiM0N1AAAAwFBMVEVHcEzh6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O3h6O2ImaYpLzPv8/b1+Pr09/nn7PBwf4m/ydGqt8Dx9fjp7vLw9Pfl6+/s8fSPn6vi6e7h6O01PECCkp/q7/PFztWjsbt8jJjn7fE7Q0nCxsicq7axvcZkcXu4w8vN1NqorrHb4OVZZG1cYWVDSExqeIJPVVhpbnFNV15BSlDS2eAvNjqerbhTXWV2hZCWpbHh5urrANQpAAAAEHRSTlMAIBCAMGDP70C/34+vn3BQ8J8JlQAAAt9JREFUeF7tmNeS4yAQRa3xWJbjNCg65zQxh83//1fbwMiAW9ZuuXj0fXPVqUv3JQhcMXTWWZdB8D/QZSlw0fWnQs1WCee1FORXvWM21fp0r7Z3BOpMtVoXheX6U1P1WhF0VbehoMBHIjHvhRHvT+R4FKpJgz6PBCStaoU+w16oFC0E1Cn02UQ5FCsn6tMPtfiEQlfChxvQSDhdWhH6tg+qNzmEvLrtg+IiJzPxlvIhkG8aNYiPqqltNCbyQYBCVTugDYE2CAXWWL2QaGjV3ZxOJxFhIkygmSMB+oxCqoFZUk02RjUyJqWtxqKKjZKaqnuq4T5KzyiIllTTU88LIb5PqYpMFBYq3o/WzguimuRLt2nOBh3NkwtNV020wADyzvgRJkKjbh51dATqIXSFTNdi6DJpCKOO1RmNu6W6jw2ATu5X+4ujUF8lWf/q/j4bA8D1XXxYdqDb58sVoFZLfpikYgZh+O035LozqYkMKVDtp+OcGacHSQZfzI0A5sn4Txgu4dpwimX/VRERzwS0TlZxyFPIuD2aYu6QSLaMPQqD1HRayLQ7IkfhcztjM9l7Bpk1WlUYxY+IfDDG3qQ//srMtJtyV49SLPkToWcJ4a/UTLshmD7m85OhXiRzPwd4NHdJpeJj2ZgP+uRGD5gT16Mpo28ACZPaCeb9A+DGNkK3FPuSjOr/7RZgaZWNRjeqMdTsYbd7Z2wOY3P+PWH0A2CmoBeEntkMYGWN1pDMd2bqFSDOITm1CAKsmaU1QIGRzTxhSNQosaHErVF5a8lpramwtUrC1iJh6+nXKpl+LTL9ekHmmpUvSKVPsiCNLaK0/VW+RZTPnGyR/aZ93cpynhAp27QSwr7IprWOkQSrgX8dI8kaGXKMODvYXB21zg5/Z58jZx9IV59sZ5cIZ9caVxctZ1c/V5dRZ9djVxd2Z08Id48a4jQcnPrMOv3h19MPPzdPUVePY0fPddd/IJx11l/gOBfaR45jVQAAAABJRU5ErkJggg=="}
}
M.Aliases = {
    smile = "happy pleased glad", laugh = "lol lmao funny joke",
    skull = "dead rip died bones", cry = "sad tear upset",
    angry = "mad annoyed grr", think = "hmm thinking consider",
    heart = "love like red", fire = "lit burn hot",
    thumbsup = "yes good ok like up", clap = "applause bravo well",
    poop = "crap trash bad", eyes = "looking watching sus",
wave = "hi hello bye greet",
    ok = "okay perfect fine",
    pray = "please thanks sorry",
    muscle = "strong flex gym",
    thumbsdown = "no bad dislike down",
    point = "right this look",
    handshake = "deal truce agree",
    facepalm = "ugh disappoint stupid",
    wink = "joke kidding sly",
    grin = "happy smile teeth",
    sob = "bawl crying weep",
    rage = "furious mad anger",
    sweat = "nervous phew close",
    cool = "sunglasses smug deal",
    nerd = "glasses smart geek",
    sleep = "tired bored zzz",
    sick = "ill fever thermometer",
    shush = "quiet secret hush",
    salute = "respect o7 yessir",
    melt = "melting awkward dying",
    ghost = "boo spooky haunt",
    alien = "ufo space grey",
    robot = "bot ai machine",
    clown = "joker fool bozo",
    devil = "evil grin imp",
    angel = "innocent halo saint",
    cat = "kitty meow feline",
    dog = "puppy woof canine",
    rat = "rodent mouse vermin",
    bug = "insect worm glitch",
    blood = "bleeding wound drop",
    pill = "meds drug capsule",
    syringe = "needle inject shot",
    bandage = "plaster patch heal",
    bone = "broken fracture skeleton",
    brain = "smart mind think",
    knife = "blade stab cut",
    bomb = "explosive tnt detonate",
    boom = "explosion collision blast",
    warning = "caution careful alert",
    check = "yes done correct tick",
    cross = "no wrong denied",
    question = "what huh ask",
    exclaim = "important alert wow",
    hundred = "100 perfect based",
    star = "favourite rating gold",
    crown = "king royal win",
    money = "cash rich bag",
    beer = "drink pub cheers",
    pizza = "food slice hungry",
    coffee = "drink cafe awake",
    clock = "alarm time late",
    lock = "locked secure closed",
    key = "unlock access door",
    mag = "search look find",
    tools = "wrench fix repair",
    car = "drive vehicle taxi",
    run = "running flee escape",
    trophy = "win first champion",
    skull2 = "crossbones danger poison",
}
-- The twelve above are embedded so the module always loads. The rest travel
-- separately: AddCSLuaFile refuses, silently, to deliver a file whose LZMA
-- size passes 64KB, and a client that never receives client.lua gets the
-- graceful-degradation stub in cl_zchat.lua instead - no button, no error,
-- nothing to notice. Absent or malformed here means twelve emoji, never a
-- broken module, which also makes a newly added client file safe to ship
-- mid-session: it fills in at the next map change.
if file.Exists("zc_chat_media/emoji_extra.lua", "LUA") then
    local ok, more = pcall(include, "zc_chat_media/emoji_extra.lua")
    if ok and istable(more) then
        for _, row in ipairs(more) do
            if istable(row) and row.name and row.sha and row.data then
                emojiData[#emojiData + 1] = row
            end
        end
    end
end

file.CreateDir("zc_chat_media_v1")
for _, row in ipairs(emojiData) do
    local path = "zc_chat_media_v1/" .. row.name .. ".png"
    local bytes = util.Base64Decode(row.data)
    if bytes and util.SHA256(bytes) == row.sha then
        local stored = file.Read(path, "DATA")
        if not stored or util.SHA256(stored) ~= row.sha then file.Write(path, bytes) end
        local mat = Material("../data/" .. path, "smooth")
        if mat and not mat:IsError() then
            M.Emojis[row.name] = {path = "../data/" .. path, material = mat}
            M.Order[#M.Order + 1] = row.name
        end
    end
end
file.Write("zc_chat_media_v1/ATTRIBUTION.txt", "Twemoji graphics copyright Twitter, Inc. and other contributors. CC BY 4.0. https://creativecommons.org/licenses/by/4.0/ Source: https://github.com/jdecked/twemoji/tree/v17.0.2 . Original unmodified PNGs; scaled for display.")

function M.Escape(text)
    return (tostring(text):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function M.Format(text, size)
    size = math.Clamp(math.floor(tonumber(size) or 18), 12, 28)
    local count = 0
    return (M.Escape(text):gsub(":([%w_]+):", function(name)
        local emoji = M.Emojis[name]
        if not emoji or count >= 24 then return ":" .. name .. ":" end
        count = count + 1
        return string.format("<img=%s,%dx%d>", emoji.path, size, size)
    end))
end

-- Still images, on the same terms GIFs already had. i.imgur.com joins the
-- allowlist because it serves direct, stable image URLs with no query; Discord's
-- CDN deliberately does not, because its links now carry an expiring signature
-- and an embed built from one is a broken image within the day.
local STILL_HOSTS = {["i.imgur.com"] = true}
local MEDIA_EXT = {gif = true, png = true, jpg = true, jpeg = true, webp = true}

-- Returns the URL unchanged and its extension, or nil. Named for GIFs because
-- every caller in the tree already asks for it by that name; it answers for any
-- allowed still image now.
function M.GIFURL(url)
    if type(url) ~= "string" or #url > 2048 then return nil end
    local host, rest = url:match("^https://([%w%.%-]+)(/[^%s]+)$")
    if not host then return nil end
    local giphy = host == "media.giphy.com" or host == "i.giphy.com" or host:match("^media[0-4]%.giphy%.com$")
    local still = STILL_HOSTS[host] or false
    if host ~= "media.tenor.com" and not giphy and not still then return nil end
    local path, query = rest:match("^([^?]+)%?(.*)$")
    if not path then path = rest end
    local ext = path:match("^/[%w_/%-%.]+%.(%w+)$")
    if not ext or path:find("..",1,true) then return nil end
    ext = ext:lower()
    if not MEDIA_EXT[ext] then return nil end
    -- Only the GIF providers get to keep a query string, and only their own
    -- tracking parameters. Every other host, image ones included, is refused
    -- outright if it carries one.
    if query and (not giphy or query == "" or query:find("[^%w_%%&=%.~+%-]")) then return nil end
    -- Preserve the provider's exact URL, including tracking query parameters.
    return url, ext
end

function M.HTMLText(value)
    return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end

function M.FindGIF(elements)
    local kind, url = M.FindMedia(elements)
    if kind == "gif" then return url end
end

function M.HTML(url)
    url = M.GIFURL(url)
    if not url then return nil end
    -- Only a validated image URL is interpolated; no chat HTML or JavaScript.
    return [[<!doctype html><html><head><meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https://media.tenor.com https://i.imgur.com https://media.giphy.com https://i.giphy.com https://media0.giphy.com https://media1.giphy.com https://media2.giphy.com https://media3.giphy.com https://media4.giphy.com; style-src 'unsafe-inline'; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<style>html,body{margin:0;background:#181b20;width:100%;height:100%;overflow:hidden}img{width:100%;height:100%;object-fit:contain;pointer-events:none}</style></head><body><img referrerpolicy="no-referrer" alt="GIF unavailable" src="]] .. M.HTMLText(url) .. [["></body></html>]]
end

-- One represented URL per message; other links and surrounding text stay intact.
-- The social pass runs first and the media scan works on its result, but the
-- verdict is still asked about the caller's table - Attach only ever sees that
-- one, and the two must not disagree about a message.
function M.DisplayElements(elements)
    local social = M.SocialElements(elements)
    -- Attach refuses to embed a spoiled link; this half has to refuse to take
    -- it out of the text, or the message loses the link AND shows no embed.
    local spoiled = M.SpoiledURLs[elements]
    for index, value in ipairs(social) do
        if type(value) == "string" then
            local offset = 1
            while true do
                local first, last = value:find("https://[^%s<>\"']+", offset)
                if not first then break end
                local url = value:sub(first, last):gsub("[%)%],!;%.]+$", "")
                if (M.GIFURL(url) or M.VideoID(url)) and not (spoiled and spoiled[url]) then
                    local display = {}
                    for i, item in ipairs(social) do display[i] = item end
                    -- A muted, purged or flooding speaker keeps the link as
                    -- readable text: the message is never quietly emptied.
                    local verdict = M.Verdict(elements)
                    if verdict ~= "allow" then
                        display[#display + 1] = M.VerdictNote(verdict)
                        return display
                    end
                    display[index] = value:sub(1, first - 1) .. value:sub(first + #url)
                    return display, url
                end
                offset = last + 1
            end
        end
    end
    return social
end

-- Video embeds. A recognized link is replaced by an inline player: the card
-- costs nothing until it is clicked, and only one video ever plays at a time.
local VIDEO_HOSTS = {["www.youtube.com"] = true, ["youtube.com"] = true,
    ["m.youtube.com"] = true, ["music.youtube.com"] = true}
local videoBack = Color(16, 18, 22)
local videoEdge = Color(76, 73, 73)
local videoMark = Color(214, 44, 44)

function M.VideoSeconds(value)
    if type(value) ~= "string" or value == "" or #value > 12 then return nil end
    local plain = value:match("^(%d+)s?$")
    if plain then return math.min(tonumber(plain), 86400) end
    if not value:find("[hms]") or not value:match("^%d*h?%d*m?%d*s?$") then return nil end
    local total = (tonumber(value:match("(%d+)h")) or 0) * 3600
        + (tonumber(value:match("(%d+)m")) or 0) * 60
        + (tonumber(value:match("(%d+)s")) or 0)
    if total <= 0 then return nil end
    return math.min(total, 86400)
end

local function queryValue(query, key)
    if type(query) ~= "string" then return nil end
    for pair in query:gmatch("[^&]+") do
        local name, value = pair:match("^([%w_%-]+)=([%w_%-]+)$")
        if name == key then return value end
    end
end

function M.VideoID(url)
    if type(url) ~= "string" or #url > 2048 then return nil end
    local host, rest = url:match("^https://([%w%.%-]+)(/[^%s]*)$")
    if not host then return nil end
    -- Hosts are case insensitive; the video id is not.
    host = host:lower()
    local path, query = rest:match("^([^?]*)%?(.*)$")
    if not path then path = rest end
    local id
    if host == "youtu.be" then
        id = path:match("^/([%w_%-]+)$")
    elseif VIDEO_HOSTS[host] then
        id = path:match("^/embed/([%w_%-]+)$") or path:match("^/shorts/([%w_%-]+)$")
            or path:match("^/live/([%w_%-]+)$")
        if not id and path == "/watch" then id = queryValue(query, "v") end
    end
    -- Every public YouTube id is eleven characters; anything else is not a video.
    if not id or #id ~= 11 then return nil end
    return id, M.VideoSeconds(queryValue(query, "t") or queryValue(query, "start") or "") or 0
end

-- The first supported link in the message is the one that gets embedded,
-- whichever kind it is; everything after it stays visible text.
function M.FindMedia(elements)
    for _, value in ipairs(elements) do
        if type(value) == "string" then
            for url in value:gmatch("https://[^%s<>\"']+") do
                url = url:gsub("[%)%],!;%.]+$", "")
                if M.GIFURL(url) then return "gif", url end
                local id, start = M.VideoID(url)
                if id then return "video", id, start end
            end
        end
    end
end

function M.InlineEnabled()
    return inlineMedia:GetBool()
end

function M.FilterRowText(row, text)
    -- GoobOS chat links (lua/zc_goobos/links.lua) draw "!settings preferences" as a link. Guarded:
    -- a fault there costs the links, never the row.
    if ZCGoobLinks and ZCGoobLinks.RenderRow then
        local ok, linked = pcall(ZCGoobLinks.RenderRow, row, text)
        if ok and type(linked) == "string" then
            text = linked
        elseif not ok and not M.GoobLinksFailed then
            M.GoobLinksFailed = true
            ErrorNoHalt("[zc_chat_media] GoobOS links: " .. tostring(linked) .. "\n")
        end
    end
    if M.InlineEnabled() then return text end
    -- Only the rendered copy changes: reports, spoilers and restore retain
    -- the original text. Hide every supported media URL, not just the embed.
    local filtered = text:gsub("https://[^%s<>\"']+", function(token)
        local url = token:gsub("[%)%],!;%.]+$", "")
        if M.GIFURL(url) or M.VideoID(url) then
            return "[media hidden]" .. token:sub(#url + 1)
        end
        return token
    end)
    if row.ZCHasInlineMedia then filtered = filtered .. " [media hidden]" end
    return filtered
end

function M.RefreshInlineMedia()
    if not M.InlineEnabled() then
        M.Stop()
        M.StopVideo()
        if IsValid(M.Expanded) then M.Expanded:Remove() end
        M.Expanded = nil
    end
    local chat = hg and hg.chat
    if not IsValid(chat) then return end
    for _, row in ipairs(ZCChatThreads and ZCChatThreads.AllRows(chat) or chat.entries or {}) do
        if IsValid(row) and row.BuildMarkup then
            row:BuildMarkup(row:GetWide())
            row:SetTall(M.TextHeight(row))
            M.Layout(row)
            row:InvalidateParent(true)
        end
    end
end

function M.EmbedURL(id, start)
    if type(id) ~= "string" or #id ~= 11 or id:find("[^%w_%-]") then return nil end
    -- modestbranding is documented as deprecated with no effect, so it is omitted.
    -- fs=0 hides the player's own fullscreen button: the Fullscreen API does not
    -- work in an offscreen CEF panel, so the control bar owns fullscreen instead.
    local url = "https://www.youtube.com/embed/" .. id
        .. "?enablejsapi=1&autoplay=1&rel=0&playsinline=1&fs=0&iv_load_policy=3"
    start = math.floor(tonumber(start) or 0)
    if start > 0 and start <= 86400 then url = url .. "&start=" .. start end
    return url
end

-- YouTube refuses to serve the embed as a top-level document (error 153,
-- "Video player configuration error"), so the panel loads this instead and the
-- embed is framed inside it. Only a validated id reaches the iframe's src, and
-- nothing from chat is interpolated anywhere in the document.
function M.VideoHTML(id, start)
    local url = M.EmbedURL(id, start)
    if not url then return nil end
    return [[<!doctype html><html><head><meta charset="utf-8">
<meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src https://www.youtube.com; style-src 'unsafe-inline'; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<style>html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%}</style>
</head><body><iframe id="zcplayer" allow="autoplay; encrypted-media" allowfullscreen src="]]
        .. M.HTMLText(url) .. [["></iframe></body></html>]]
end

local function thumbPath(id) return "zc_chat_media_v1/yt_" .. id .. ".jpg" end

local function validJPEG(body)
    return type(body) == "string" and #body >= 128 and #body <= 524288
        and body:sub(1, 3) == "\255\216\255"
end

local function thumbMaterial(id)
    local path = thumbPath(id)
    -- Material() caches per path for the rest of the session, so only ask for one
    -- after the file is on disk AND is really a JPEG: a truncated write from an
    -- earlier session would otherwise poison this id until the client restarts.
    if not file.Exists(path, "DATA") then return nil end
    if not validJPEG(file.Read(path, "DATA")) then file.Delete(path); return nil end
    local material = Material("../data/" .. path, "smooth")
    if material and not material:IsError() then return material end
end

-- The cap counts cached FILES, not fetches, so it survives a map change. Over
-- the cap, the oldest are dropped; nothing else writes to this prefix.
local function countThumbs()
    local names = file.Find("zc_chat_media_v1/yt_*.jpg", "DATA")
    if not names then return 0 end
    if #names <= 64 then return #names end
    local rows = {}
    for _, name in ipairs(names) do
        rows[#rows + 1] = {name = name, time = file.Time("zc_chat_media_v1/" .. name, "DATA") or 0}
    end
    table.sort(rows, function(a, b) return a.time > b.time end)
    for index = 49, #rows do file.Delete("zc_chat_media_v1/" .. rows[index].name) end
    return 48
end
M.ThumbCount = countThumbs()

function M.Thumbnail(id)
    if type(id) ~= "string" or #id ~= 11 or id:find("[^%w_%-]") then return nil end
    local entry = M.Thumbs[id]
    if entry then return entry.material end
    local material = thumbMaterial(id)
    if material then M.Thumbs[id] = {material = material}; return material end
    -- Two at a time, and a ceiling on how many a session will ever cache.
    if (M.ThumbRequests or 0) >= 2 or (M.ThumbCount or 0) >= 64 then return nil end
    M.ThumbRequests = (M.ThumbRequests or 0) + 1
    M.ThumbCount = (M.ThumbCount or 0) + 1
    M.Thumbs[id] = {pending = true}
    local function finished(ok, body)
        M.ThumbRequests = math.max(0, (M.ThumbRequests or 1) - 1)
        -- Only a real JPEG becomes a file; a redirect or error page must not.
        if not ok or not validJPEG(body) then
            M.Thumbs[id] = {failed = true}
            return
        end
        file.Write(thumbPath(id), body)
        M.Thumbs[id] = {material = thumbMaterial(id)}
    end
    http.Fetch("https://i.ytimg.com/vi/" .. id .. "/mqdefault.jpg",
        function(body, _, _, code) finished(code == nil or code == 200, body) end,
        function() finished(false) end)
end

function M.VideoCardPaint(card, width, height)
    local row = card:GetParent()
    local alpha = IsValid(row) and M.Alpha(row) or 255
    if alpha <= 0 then return end
    surface.SetDrawColor(videoBack.r, videoBack.g, videoBack.b, alpha)
    surface.DrawRect(0, 0, width, height)
    local material = M.Thumbnail(card.ZCVideoID)
    if material then
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.SetMaterial(material)
        surface.DrawTexturedRect(0, 0, width, height)
        surface.SetDrawColor(0, 0, 0, alpha * 0.3)
        surface.DrawRect(0, 0, width, height)
    end
    surface.SetDrawColor(videoEdge.r, videoEdge.g, videoEdge.b, alpha)
    surface.DrawOutlinedRect(0, 0, width, height)
    local size = math.min(40, math.floor(height * 0.36))
    local x, y = width * 0.5, height * 0.5
    draw.NoTexture()
    surface.SetDrawColor(videoMark.r, videoMark.g, videoMark.b,
        alpha * (card:IsHovered() and 1 or 0.85))
    surface.DrawPoly({
        {x = x - size * 0.4, y = y - size * 0.55},
        {x = x + size * 0.6, y = y},
        {x = x - size * 0.4, y = y + size * 0.55},
    })
end

-- The only commands this module ever sends. Nothing from chat reaches here,
-- and an unknown name is refused rather than concatenated into the page.
local VIDEO_COMMANDS = {playVideo = true, pauseVideo = true, mute = true,
    unMute = true, setVolume = true}

function M.VideoCommand(func, value)
    if not IsValid(M.VideoBrowser) or not VIDEO_COMMANDS[func] then return end
    local args = value and string.format("%d", math.floor(value)) or ""
    -- The listening handshake opens the widget channel; sending it with every
    -- command keeps this correct whenever the iframe finished loading.
    M.VideoBrowser:RunJavascript(
        "(function(){var f=document.getElementById('zcplayer');"
        .. "if(!f||!f.contentWindow){return;}"
        .. "f.contentWindow.postMessage(JSON.stringify({event:'listening',id:1,channel:'widget'}),'*');"
        .. "f.contentWindow.postMessage(JSON.stringify({event:'command',func:'" .. func
        .. "',args:[" .. args .. "]}),'*');})();")
end

local function videoLevel()
    return math.Clamp(math.floor(tonumber(videoVolume:GetInt()) or 40), 0, 100)
end

function M.ApplyVideoAudio()
    M.VideoCommand(M.VideoMuted and "mute" or "unMute")
    M.VideoCommand("setVolume", videoLevel())
end

function M.VideoStart()
    if not IsValid(M.VideoBrowser) then return end
    M.VideoCommand("playVideo")
    M.ApplyVideoAudio()
end

function M.UpdateVideoButtons()
    if IsValid(M.VideoPauseButton) then
        M.VideoPauseButton:SetText(M.VideoPlaying and "Pause" or "Play")
    end
    if IsValid(M.VideoMuteButton) then
        M.VideoMuteButton:SetText(M.VideoMuted and "Unmute" or "Mute")
    end
    if IsValid(M.VideoFullButton) then
        M.VideoFullButton:SetText(IsValid(M.VideoFull) and "Exit full" or "Fullscreen")
    end
end

function M.SetVideoPaused(paused)
    if not IsValid(M.VideoBrowser) then return end
    M.VideoPlaying = not paused
    if paused then M.VideoCommand("pauseVideo") else M.VideoStart() end
    M.UpdateVideoButtons()
end

function M.BuildVideoBar(row)
    local bar = vgui.Create("DPanel", row)
    if not IsValid(bar) then return end
    M.VideoBar = bar
    bar.Paint = function(_, width, height)
        surface.SetDrawColor(videoBack.r, videoBack.g, videoBack.b, 240)
        surface.DrawRect(0, 0, width, height)
    end
    local function add(text, wide, click)
        local button = vgui.Create("DButton", bar)
        button:SetText(text); button:SetWide(wide)
        button:Dock(LEFT); button:DockMargin(2, 2, 0, 2)
        button:SetKeyboardInputEnabled(false)
        button.DoClick = click
        return button
    end
    M.VideoFullButton = add("Fullscreen", 74, function() M.ToggleVideoFullscreen() end)
    M.VideoCloseButton = add("Close", 52, function() M.StopVideo() end)
    M.UpdateVideoButtons()
end

function M.MountVideo()
    if not IsValid(M.VideoBrowser) then return end
    if IsValid(M.VideoFull) then
        local width, height = ScrW(), ScrH()
        M.VideoBrowser:SetParent(M.VideoFull)
        M.VideoBrowser:SetPos(0, 0); M.VideoBrowser:SetSize(width, height - 30)
        M.VideoBrowser:SetAlpha(255)
        if IsValid(M.VideoBar) then
            M.VideoBar:SetParent(M.VideoFull)
            M.VideoBar:SetPos(0, height - 30); M.VideoBar:SetSize(width, 30)
        end
    elseif IsValid(M.VideoRow) then
        M.VideoBrowser:SetParent(M.VideoRow)
        if IsValid(M.VideoBar) then M.VideoBar:SetParent(M.VideoRow) end
        M.Layout(M.VideoRow)
        M.VideoRow:InvalidateParent(true)
    end
    if IsValid(M.VideoBar) then M.VideoBar:MoveToFront() end
end

function M.ToggleVideoFullscreen()
    if not IsValid(M.VideoBrowser) then return end
    if IsValid(M.VideoFull) then
        local frame = M.VideoFull
        M.VideoFull = nil
        M.MountVideo()
        frame:Remove()
        M.UpdateVideoButtons()
        return
    end
    local frame = vgui.Create("DFrame")
    if not IsValid(frame) then return end
    M.VideoFull = frame
    frame:SetTitle(""); frame:ShowCloseButton(false)
    frame:SetDraggable(false); frame:SetSizable(false)
    frame:SetSize(ScrW(), ScrH()); frame:SetPos(0, 0); frame:MakePopup()
    frame.Paint = function(_, width, height)
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, width, height)
    end
    frame.OnRemove = function()
        if M.VideoFull ~= frame then return end
        M.VideoFull = nil
        -- Closed from outside the control bar: keep playing in the row if the
        -- player outlived the frame, otherwise let it go.
        if IsValid(M.VideoBrowser) and IsValid(M.VideoRow) then
            M.MountVideo()
            M.UpdateVideoButtons()
        else
            M.StopVideo()
        end
    end
    M.MountVideo()
    M.UpdateVideoButtons()
end

function M.StopVideo()
    local row, frame = M.VideoRow, M.VideoFull
    M.VideoRow, M.VideoFull = nil, nil
    if IsValid(M.VideoBrowser) then M.VideoBrowser:Remove() end
    if IsValid(M.VideoBar) then M.VideoBar:Remove() end
    if IsValid(frame) then frame:Remove() end
    M.VideoBrowser, M.VideoBar = nil, nil
    M.VideoPauseButton, M.VideoMuteButton = nil, nil
    M.VideoFullButton, M.VideoCloseButton = nil, nil
    M.VideoPlaying = false
    if IsValid(row) then M.Layout(row); row:InvalidateParent(true) end
end

function M.PlayVideo(row)
    if not M.InlineEnabled() then return end
    if not IsValid(row) or not row.ZCVideoID or not videos:GetBool() then return end
    if M.VideoRow == row and IsValid(M.VideoBrowser) then return end
    if not M.EmbedURL(row.ZCVideoID, row.ZCVideoStart) then return end
    M.StopVideo()
    local browser = vgui.Create("DHTML", row)
    if not IsValid(browser) then return end
    M.VideoRow, M.VideoBrowser, M.VideoPlaying = row, browser, true
    browser:SetAllowLua(false)
    browser:SetKeyboardInputEnabled(false)
    browser:SetMouseInputEnabled(true)
    browser:SetAlpha(M.Alpha(row))
    M.BuildVideoBar(row)
    M.Layout(row)
    row:InvalidateParent(true)
    if IsValid(M.VideoBar) then M.VideoBar:MoveToFront() end
    -- CEF's SetHTML page has no usable Referer for YouTube's iframe player.
    -- Keep the normal watch page inside our DHTML card and focus its player.
    local url = "https://www.youtube.com/watch?v=" .. row.ZCVideoID
    local start = math.floor(tonumber(row.ZCVideoStart) or 0)
    if start > 0 and start <= 86400 then url = url .. "&t=" .. start .. "s" end
    browser:OpenURL(url)
    local focus = [[(function(){var p=document.getElementById('movie_player');if(!p)return;
document.documentElement.style.overflow='hidden';document.body.style.overflow='hidden';
p.style.setProperty('position','fixed','important');p.style.setProperty('left','0','important');
p.style.setProperty('top','0','important');p.style.setProperty('width','100vw','important');
p.style.setProperty('height','100vh','important');p.style.setProperty('z-index','2147483647','important');})()]]
    for _, delay in ipairs({1, 2.5, 5}) do
        timer.Simple(delay, function()
            if M.VideoBrowser == browser and IsValid(browser) then browser:RunJavascript(focus) end
        end)
    end
end

function M.TextHeight(row)
    return row.ZCBaseHeight or (row.markup and row.markup:GetHeight()) or 0
end

function M.VideoVisible(row)
    if ZCChatThreads and not ZCChatThreads.Visible(row) then return false end
    local chat = hg and hg.chat
    if not IsValid(row) or not IsValid(chat) or not videos:GetBool() or not M.InlineEnabled() then return false end
    if IsValid(M.Picker) or not row.markup then return false end
    if not row:IsVisible() or not chat:IsVisible() or not IsValid(chat.history) then return false end
    -- Unlike a GIF, a video carries audio, so it only runs while chat is open.
    if not chat:GetActive() or chat.phonePage ~= "chat" then return false end
    local _, y = row:LocalToScreen(0, M.TextHeight(row) + 4)
    local _, top = chat.history:LocalToScreen(0, 0)
    local window = chat.history:GetTall()
    -- Measure against the embed's own height: playing stops once the picture has
    -- actually left the history, not while most of it is still on screen.
    local embed = math.floor(math.max(64, math.min(480, ScrH() * 0.45, row:GetWide())) * 9 / 16)
    return window > 0 and y < top + window and y + embed > top
end

function M.LayoutVideo(row)
    if M.InlineEnabled() then M.Thumbnail(row.ZCVideoID) end
    if not row.markup then return end
    local base = M.TextHeight(row)
    local show = videos:GetBool()
    local width = math.max(64, math.min(480, ScrH() * 0.45, row:GetWide()))
    local height = show and math.floor(width * 9 / 16) or 16
    -- Owning the player and showing it inline are different things: while the
    -- player is fullscreen the row still owns it, and must not offer a play card.
    local owns = M.VideoRow == row and IsValid(M.VideoBrowser)
    local inline = owns and not IsValid(M.VideoFull)
    local bar = show and 26 or 0
    -- Reserve the embed AND the control bar up front, whether or not this row is
    -- the one playing: starting or stopping a video never shifts the history.
    row:SetTall(base + 4 + height + bar)
    if IsValid(row.ZCVideoCard) then
        row.ZCVideoCard:SetPos(0, base + 4)
        row.ZCVideoCard:SetSize(width, height)
        row.ZCVideoCard:SetVisible(show and not owns)
    end
    if inline then
        M.VideoBrowser:SetPos(0, base + 4); M.VideoBrowser:SetSize(width, height)
        if IsValid(M.VideoBar) then
            M.VideoBar:SetPos(0, base + 4 + height); M.VideoBar:SetSize(width, 26)
        end
    end
end

function M.AttachVideo(row, id, start)
    local card = vgui.Create("DButton", row)
    if not IsValid(card) then return false end
    row.ZCVideoID, row.ZCVideoStart = id, start
    row.ZCVideoCard = card
    card.ZCVideoID = id
    card:SetText("")
    card:SetKeyboardInputEnabled(false)
    card.Paint = M.VideoCardPaint
    card.DoClick = function() M.PlayVideo(row) end
    if M.InlineEnabled() then M.Thumbnail(id) end
    return true
end

function M.UpdateVideo()
    if not M.VideoRow then return end
    if not IsValid(M.VideoRow) or not IsValid(M.VideoBrowser) then M.StopVideo(); return end
    -- Fullscreen is an explicit "I want to watch this": it is not parented to
    -- the chat row, carries its own controls, and deliberately keeps playing
    -- when chat closes. Everything else follows the row's visibility.
    if IsValid(M.VideoFull) then return end
    if not videos:GetBool() then M.StopVideo(); return end
    local alpha = M.Alpha(M.VideoRow)
    M.VideoBrowser:SetAlpha(alpha)
    if IsValid(M.VideoBar) then M.VideoBar:SetAlpha(alpha) end
    -- The watch page has no iframe API; removing the panel stops its audio.
    if not M.VideoVisible(M.VideoRow) then M.StopVideo() end
end

function M.Layout(row)
    M.LayoutReport(row)
    M.LayoutReaction(row)
    M.LayoutModeration(row)
    if IsValid(row.ZCReveal) then
        row.ZCReveal:SetPos(math.max(0, row:GetWide() - 74), 1)
    end
    if not M.InlineEnabled() then
        for _, key in ipairs({"ZCVideoCard", "ZCGifPlaceholder", "ZCExpandHit"}) do
            if IsValid(row[key]) then row[key]:SetVisible(false) end
        end
        row:SetTall(M.TextHeight(row))
        return
    end
    if row.ZCVideoID then return M.LayoutVideo(row) end
    if not row.ZCGifURL or not row.markup then return end
    local base = M.TextHeight(row)
    local show = gifs:GetBool()
    local width = math.max(1, math.min(260, row:GetWide()))
    -- Reserve the embed's space even while offscreen: scrolling never shifts it.
    row:SetTall(base + (show and 128 or 20))
    if IsValid(row.ZCGifPlaceholder) then
        row.ZCGifPlaceholder:SetPos(0, base + 4)
        row.ZCGifPlaceholder:SetSize(width, show and 120 or 16)
        row.ZCGifPlaceholder:SetText(show and "GIF" or "GIFs disabled")
        row.ZCGifPlaceholder:SetVisible(not IsValid(row.ZCGifBrowser))
    end
    if IsValid(row.ZCGifBrowser) then
        row.ZCGifBrowser:SetPos(0, base + 4)
        row.ZCGifBrowser:SetSize(width, 120)
    end
    if IsValid(row.ZCExpandHit) then
        row.ZCExpandHit:SetPos(0, base + 4)
        row.ZCExpandHit:SetSize(width, show and 120 or 16)
        row.ZCExpandHit:SetVisible(show)
    end
end

function M.Stop(row)
    if not row then
        for item in pairs(M.Rows) do M.Stop(item) end
        return
    end
    local hadBrowser = row.ZCGifBrowser ~= nil
    if IsValid(row.ZCGifBrowser) then row.ZCGifBrowser:Remove() end
    row.ZCGifBrowser = nil
    if hadBrowser and IsValid(row) then M.Layout(row) end
end

function M.Alpha(row)
    if ZCChatThreads and not ZCChatThreads.Visible(row) then return 0 end
    local chat = hg and hg.chat
    if not IsValid(chat) then return 0 end
    if chat:GetActive() and chat.phonePage ~= "chat" then return 0 end
    if chat:GetActive() then return math.Clamp(math.max(chat.alpha or 0, row.alpha or 0), 0, 255) end
    return math.Clamp((row.alpha or 0) - (255 - (chat.realAlpha or 0)), 0, 255)
end

function M.Visible(row)
    if ZCChatThreads and not ZCChatThreads.Visible(row) then return false end
    local chat = hg and hg.chat
    if not IsValid(row) or not IsValid(chat) or not gifs:GetBool() or not M.InlineEnabled() or IsValid(M.Picker) then return false end
    if not row:IsVisible() or not chat:IsVisible() or not IsValid(chat.history) or M.Alpha(row) <= 0 then return false end
    local _, y = row:LocalToScreen(0, M.TextHeight(row) + 4)
    local _, top = chat.history:LocalToScreen(0, 0)
    local height = chat.history:GetTall()
    return height > 0 and y < top + height and y + 120 > top
end

function M.Play(row)
    if not M.Visible(row) or IsValid(row.ZCGifBrowser) then return end
    local count = 0
    for item in pairs(M.Rows) do if IsValid(item.ZCGifBrowser) then count = count + 1 end end
    if count >= 3 or RealTime() < (M.NextCreate or 0) then return end
    local html = M.HTML(row.ZCGifURL)
    if not html then return end
    M.NextCreate = RealTime() + 0.2
    local browser = vgui.Create("DHTML", row)
    if not IsValid(browser) then return end
    row.ZCGifBrowser = browser
    browser:SetAllowLua(false)
    browser:SetMouseInputEnabled(false); browser:SetKeyboardInputEnabled(false)
    browser:SetAlpha(M.Alpha(row))
    M.Layout(row)
    browser:SetHTML(html)
end

-- Social polish. Mentions, a clock, speaker grouping, an unread pill and tab
-- completion. All of it is presentation decided on this client, and all of it
-- hangs off what cl_zchat.lua already calls: DisplayElements and Attach with
-- the same table once per message, and InstallButton once at startup. That file
-- is deliberately not touched - its load guard pins this module's version, and
-- a mismatch drops every client to stock chat.
local Timestamps = CreateClientConVar("zc_chat_timestamps", "0", true, false,
    "Show a clock beside each chat message", 0, 1)
local Grouping = CreateClientConVar("zc_chat_group", "1", true, false,
    "Omit a repeated speaker name on consecutive messages", 0, 1)
local Pinging = CreateClientConVar("zc_chat_ping", "0", true, false,
    "Play a cue and tint the row when someone mentions you", 0, 1)

local MENTION_COLOR = Color(255, 205, 100)
local MENTION_SELF = Color(126, 232, 158)
local STAMP_COLOR = Color(136, 133, 133)
local DEFAULT_COLOR = Color(255, 255, 255)
local GROUP_WINDOW = 30
local PING_COOLDOWN = 3
local NICK_CACHE = 5

M.Pings = setmetatable({}, {__mode = "k"})
M.Social = setmetatable({}, {__mode = "k"})
M.Unread = 0
M.AtBottom = true

-- Longest nick first, so "@Bob" can never win over "@Bobby" while both are
-- connected. Rebuilt when the roster size changes or the cache ages out; a
-- five second wait to be mentionable is cheaper than sorting every message.
function M.NickList()
    local players = player.GetAll()
    if M.Nicks and M.NickCount == #players and RealTime() < (M.NickStamp or 0) + NICK_CACHE then
        return M.Nicks
    end
    local list = {}
    for _, ply in ipairs(players) do
        if IsValid(ply) then
            local nick = ply:Nick()
            if type(nick) == "string" and nick ~= "" then
                list[#list + 1] = {ply = ply, nick = nick, lower = nick:lower()}
            end
        end
    end
    table.sort(list, function(a, b) return #a.nick > #b.nick end)
    M.Nicks, M.NickCount, M.NickStamp = list, #players, RealTime()
    return list
end

-- Split a chat string around "@nick" so the name can carry its own colour.
-- Splitting beats writing markup into the text: M.Format escapes < and >, so a
-- colour tag put there would render as literal characters.
function M.SplitMentions(value, resume, out)
    if type(value) ~= "string" then return false, false end
    -- Links are stepped over rather than the whole message being skipped: an
    -- "@" inside a URL is part of the URL, and cutting one in half would hide
    -- it from the embed scan that runs next. Guarding only the link itself
    -- means "@someone look <link>" keeps both halves. Same pattern
    -- DisplayElements uses, so the two agree on where a link ends.
    local spans
    if value:find("https://", 1, true) then
        spans = {}
        local from = 1
        while true do
            local first, last = value:find("https://[^%s<>\"']+", from)
            if not first then break end
            spans[#spans + 1] = {first, last}
            from = last + 1
        end
    end
    local list = M.NickList()
    local me = LocalPlayer and LocalPlayer()
    local pinged, offset, cut = false, 1, 1
    while true do
        local at = value:find("@", offset, true)
        if not at then break end
        local hit
        if spans then
            for _, span in ipairs(spans) do
                if at >= span[1] and at <= span[2] then at = nil break end
            end
        end
        if not at then
            offset = offset + 1
        else
        for _, entry in ipairs(list) do
            if value:sub(at + 1, at + #entry.nick):lower() == entry.lower then
                -- A letter straight after means the name only looked matched.
                local after = value:sub(at + #entry.nick + 1, at + #entry.nick + 1)
                if after == "" or not after:match("[%w_]") then hit = entry end
                break
            end
        end
        if hit then
            local isMe = IsValid(me) and hit.ply == me
            if at > cut then out[#out + 1] = value:sub(cut, at - 1) end
            out[#out + 1] = isMe and MENTION_SELF or MENTION_COLOR
            out[#out + 1] = "@" .. hit.nick
            out[#out + 1] = resume
            cut = at + #hit.nick + 1
            offset = cut
            if isMe then pinged = true end
        else
            offset = at + 1
        end
        end
    end
    if cut == 1 then return false, false end
    if cut <= #value then out[#out + 1] = value:sub(cut) end
    return true, pinged
end

-- "Same speaker, recently." Tracked by steamid64, so a name change mid-stream
-- cannot make two people look like one, or one person look like two.
function M.GroupSpeaker(speaker)
    if not Grouping:GetBool() then return false end
    local steam = IsValid(speaker) and speaker:SteamID64()
    if type(steam) ~= "string" then return false end
    local now = RealTime()
    local same = M.LastSpeaker == steam and now < (M.LastSpoke or 0) + GROUP_WINDOW
    M.LastSpeaker, M.LastSpoke = steam, now
    return same
end

function M.Ping()
    if M.Restoring or not Pinging:GetBool() then return end
    local now = RealTime()
    -- Not (M.LastPing or 0): RealTime is small just after a map load, and
    -- comparing against zero swallowed the first cue of the session.
    if M.LastPing and now < M.LastPing + PING_COOLDOWN then return end
    M.LastPing = now
    surface.PlaySound("buttons/button15.wav")
end

-- The table cl_zchat will render. Never the caller's table: the report flow,
-- the media verdict and the flood budget all key off that one by identity, and
-- it is also what AddLine formats to restore a stripped message.
-- BEGIN CHAT IDENTITY: server-replicated metadata, presentation only.
M.IdentityVersion = "20260923.settings2"
M.IdentityTiers = {
    {hours=0, name="Fresh join", color=Color(218,226,237)},
    {hours=2, name="Newcomer", color=Color(163,225,195)},
    {hours=10, name="Regular", color=Color(111,218,220)},
    {hours=50, name="Seasoned", color=Color(135,187,255)},
    {hours=150, name="Veteran", color=Color(202,173,250)},
    {hours=500, name="Old-timer", color=Color(244,207,132)}
}
local identityRanks = {
    operator={name="Operator", icon="icon16/shield.png"},
    ["community manager"]={name="Community Manager", icon="icon16/group_gear.png"},
    admin={name="Admin", icon="icon16/star.png"},
    superadmin={name="Superadmin", icon="icon16/medal_gold_1.png"}
}
function M.IdentityTier(seconds)
    if not isnumber(seconds) or seconds < 0 or seconds ~= seconds then return nil end
    local tier = M.IdentityTiers[1]
    for _, candidate in ipairs(M.IdentityTiers) do
        if seconds < candidate.hours * 3600 then break end
        tier = candidate
    end
    return tier
end
function M.CaptureIdentity(elements, speaker, steam, name)
    -- A row keeps its identity snapshot across regrouping, tab switches and disconnects.
    if elements.zcIdentity then return elements.zcIdentity end
    local index
    for i, value in ipairs(elements) do
        if type(value) == "Player" and IsValid(value) and value == speaker then index=i; break end
    end
    if not index and elements.zcPrivate and elements[2] == elements.zcSenderName then index=2 end
    if not index then return end
    if not IsValid(speaker) and isstring(steam) then
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == steam then speaker=ply; break end
        end
    end
    local identity={index=index, name=tostring(name or elements.zcSenderName or "Player")}
    if IsValid(speaker) then
        identity.name=speaker:Nick()
        identity.bot=speaker:IsBot()
        if not identity.bot then
            local seconds=speaker:GetNWInt("ZCPlaytimeTotal", -1)
            if seconds < 0 then seconds=speaker:GetNWInt("PlayTime", -1) end
            identity.seconds=seconds >= 0 and seconds or nil
            local rank=string.lower(speaker:GetUserGroup() or "user")
            -- Exact custom rank first; inherited staff groups retain their base badge.
            if not identityRanks[rank] then
                if speaker:IsSuperAdmin() then rank="superadmin"
                elseif speaker:IsAdmin() then rank="admin"
                elseif speaker.CheckGroup and speaker:CheckGroup("operator") then rank="operator" end
            end
            if identityRanks[rank] then identity.rank=rank end
        end
    end
    elements.zcIdentity=identity
    return identity
end
function M.IdentityMarkup(identity)
    local tier=M.IdentityTier(identity.seconds)
    local color=tier and tier.color or Color(227,224,224)
    local name=tostring(identity.name):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    local text=string.format("<color=%d,%d,%d>%s", color.r,color.g,color.b,name)
    local rank=identityRanks[identity.rank]
    if rank then text=text.." <color=255,255,255><img="..rank.icon..",20x20>" end
    return text.."<color=230,237,246>"
end
function M.IdentityTooltip(identity)
    if not identity then return end
    local tier=M.IdentityTier(identity.seconds)
    local rank=identityRanks[identity.rank]
    local detail=identity.bot and "Bot" or (tier and (tier.name.." · "..math.floor(identity.seconds/3600).."h played") or "Playtime unavailable")
    return identity.name.."\n"..detail..(rank and ("\n"..rank.name) or "")
end
-- END CHAT IDENTITY

-- BEGIN CHAT SCROLL: exact text-line movement; velocity changes presentation only.
function M.ScrollLineHeight()
    surface.SetFont("zChatFont")
    local _, height=surface.GetTextSize("Mg")
    return math.max(1,math.floor(height+0.5))
end
function M.ScrollMotion(state, travel, dt)
    dt=math.max(0.001,math.min(dt,0.1))
    local speed=math.abs(travel)/dt
    local response=1-math.exp(-dt/(speed>state.speed and 0.055 or 0.16))
    state.speed=state.speed+(speed-state.speed)*response
    if travel~=0 then state.direction=travel>0 and 1 or -1 end
    state.amplitude=9*(1-math.exp(-state.speed/650))
    if state.amplitude<0.025 then state.amplitude=0;state.speed=0 end
    state.phase=(state.phase+dt*(9+math.min(state.speed/240,9))*state.direction)%(math.pi*2)
end
function M.ScrollWave(state, position, own)
    -- Bend inward, keeping edge bubbles and their avatars inside the history clip.
    local wave=(0.5+0.5*math.sin(position*math.pi*2-state.phase))*state.amplitude
    return own and -wave or wave
end
function M.UpdateScroll(chat)
    local history=chat.history
    if not IsValid(history) then return end
    local bar=history:GetVBar()
    local now=RealTime()
    if history.ZCLineScrollVersion~=M.Version then
        history.ZCLineScrollVersion=M.Version
        history.ZCRowScrollInstalled=true
        history.ZCRowScroll=nil -- retire the old row-target spring
        local function wheel(_,delta)
            if delta==0 or chat.history~=history or not chat:GetActive() or chat.phonePage~="chat" then return true end
            local remainder=(history.ZCWheelRemainder or 0)+delta
            local lines=remainder>0 and math.floor(remainder) or math.ceil(remainder)
            history.ZCWheelRemainder=remainder-lines
            if lines==0 then return true end
            chat.scrollStart=nil
            local current=bar:GetScroll()
            bar:SetScroll(math.Clamp(current-lines*M.ScrollLineHeight(),0,math.max(0,bar.CanvasSize or 0)))
            history.ZCWheelAt=RealTime()
            -- Capture the real displacement, including clamping at either edge.
            history.ZCWheelTravel=(history.ZCWheelTravel or 0)+bar:GetScroll()-current
            return true
        end
        history.OnMouseWheeled=wheel
        bar.OnMouseWheeled=wheel
    end
    local active=chat:GetActive() and chat.phonePage=="chat"
    local switched=chat.ZCScrollHistory~=history
    chat.ZCScrollHistory=history
    local state=history.ZCScrollMotion
    if not state or switched or not active or chat.scrollStart or (ZCPhoneSettings and ZCPhoneSettings.ReducedMotion()) then
        state={last=bar:GetScroll(),at=now,speed=0,amplitude=0,phase=0,direction=1}
        history.ZCScrollMotion=state
        history.ZCWheelTravel=0
        if switched or not active then history.ZCWheelRemainder=0 end
    else
        local travel=history.ZCWheelTravel or 0
        if bar.Dragging or state.dragging then travel=bar:GetScroll()-state.last end
        M.ScrollMotion(state,travel,now-state.at)
        state.last=bar:GetScroll();state.at=now;state.dragging=bar.Dragging
        history.ZCWheelTravel=0
    end
    for _,row in ipairs(chat.entries) do
        if IsValid(row) then
            local shift=0
            if active and state.amplitude>0 then
                local center=row:GetY()-bar:GetScroll()+row:GetTall()/2
                if center>-row:GetTall()/2 and center<history:GetTall()+row:GetTall()/2 then
                    local position=math.Clamp(center/math.max(1,history:GetTall()),0,1)
                    shift=M.ScrollWave(state,position,row.ZCOwn) * ((ZCPhoneSettings and ZCPhoneSettings.Get("wave") or 100)/100)
                end
            end
            if math.abs((row.ZCWaveX or 0)-shift)>0.05 or (shift==0 and row.ZCWaveX~=0) then
                row:SetX(shift);row.ZCWaveX=shift
            end
        end
    end
end
-- END CHAT SCROLL

function M.SocialElements(elements)
    if type(elements) ~= "table" then return elements end
    local cached = M.Social[elements]
    if cached then return cached end
    local speaker = M.ReportSpeaker(elements)
    local grouped = elements.zcGrouped == true
    local out = {}
    if Timestamps:GetBool() then
        out[#out + 1] = STAMP_COLOR
        out[#out + 1] = os.date("[%H:%M] ", elements.zcTimestamp)
    end
    local resume, pinged, dropped, once = DEFAULT_COLOR, false, false, false
    local spoil = {count = 0, list = {}, urls = {}}
    for index, value in ipairs(elements) do
        if elements.zcIdentity and index == elements.zcIdentity.index then
            if grouped then
                once, dropped = true, true
            else
                out[#out + 1] = {zcIdentityHeader=elements.zcIdentity}
            end
        elseif type(value) == "Player" and IsValid(value) then
            resume = team.GetColor(value:Team()) or DEFAULT_COLOR
            if grouped and value == speaker and not once then
                -- The name goes, its colour stays: the line still reads as
                -- theirs, it just stops repeating who is talking.
                once, dropped = true, true
                out[#out + 1] = resume
            else
                out[#out + 1] = value
            end
        elseif istable(value) and value.r and value.g and value.b then
            resume = value
            out[#out + 1] = value
        elseif type(value) == "string" then
            local text = M.MaskSpoilers(value, spoil)
            if grouped and index == 2 and value == ":skull: " and (elements[4] == speaker or (elements.zcIdentity and elements.zcIdentity.index == 4)) then text = "" end
            if grouped and elements.zcPrivate and index == 2 and value == elements.zcSenderName then text = ""; dropped = true end
            if dropped then
                -- Drop the separator the removed name was hanging off.
                local trimmed = text:match("^%s*:%s?(.*)$")
                if trimmed then text = trimmed end
                dropped = false
            end
            local split, hit = M.SplitMentions(text, resume, out)
            if hit then pinged = true end
            if not split then out[#out + 1] = text end
        else
            dropped = false
            out[#out + 1] = value
        end
    end
    if pinged then M.Pings[elements] = true; M.Ping() end
    if spoil.count > 0 then M.Spoilers[elements] = spoil.list; M.SpoiledURLs[elements] = spoil.urls end
    M.Social[elements] = out
    return out
end

-- Called once per message from Attach. Only counts while the reader is holding
-- position above the bottom, which is the only time the pill has anything to say.
function M.NoteMessage()
    if M.Restoring or (hg and IsValid(hg.chat) and hg.chat.ZCRoutingInactive) or M.AtBottom then return end
    M.Unread = math.min((M.Unread or 0) + 1, 999)
end

function M.MentionPaint(row)
    if row.ZCMention then return end
    row.ZCMention = true
    local base = row.Paint
    row.Paint = function(self, w, h)
        local alpha = math.Clamp(tonumber(self.alpha) or 0, 0, 255)
        if alpha > 0 then
            surface.SetDrawColor(MENTION_SELF.r, MENTION_SELF.g, MENTION_SELF.b, alpha * 0.14)
            surface.DrawRect(0, 0, w, h)
        end
        if base then return base(self, w, h) end
    end
end

function M.AttachSocial(row, elements)
    M.NoteMessage()
    if IsValid(row) and M.Pings[elements] then M.MentionPaint(row) end
end

function M.ScrollToBottom(chat)
    if not IsValid(chat) then return false end
    local bar = IsValid(chat.history) and chat.history:GetVBar()
    if not IsValid(bar) then return false end
    bar:SetScroll(bar.CanvasSize)
    M.Unread = 0
    M.AtBottom = true
    if IsValid(chat.entry) then chat.entry:RequestFocus() end
    return true
end

local PILL_WIDE = 190

-- AddLine already refuses to jump when the reader has scrolled up; what it
-- never did was say that anything had arrived. This is only that missing half.
function M.InstallPill(chat)
    if not IsValid(chat) or IsValid(chat.ZCUnread) then return end
    local pill = vgui.Create("DButton", chat)
    chat.ZCUnread = pill
    pill:SetZPos(2)
    pill:SetText("")
    pill:SetVisible(false)
    pill.Paint = function(self, w, h)
        surface.SetDrawColor(36, 33, 33, 240)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(MENTION_SELF.r, MENTION_SELF.g, MENTION_SELF.b, 220)
        surface.DrawRect(0, 0, w, 1)
        draw.SimpleText(self.ZCLabel or "", "zChatFontSmall", w * 0.5, h * 0.5,
            color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    pill.DoClick = function() M.ScrollToBottom(chat) end
    pill.Think = function(self) M.PillThink(chat, self) end
end

function M.PillThink(chat, pill)
    if not IsValid(chat) or not IsValid(chat.history) then return end
    local bar = chat.history:GetVBar()
    if not IsValid(bar) then return end
    -- CanvasSize is the largest Scroll can be, so equality is the bottom. Two
    -- pixels of slack absorbs the rounding a freshly added row introduces.
    M.AtBottom = (tonumber(bar.Scroll) or 0) >= (tonumber(bar.CanvasSize) or 0) - 2
    if M.AtBottom then M.Unread = 0 end
    local show = chat:GetActive() and chat.phonePage == "chat" and (M.Unread or 0) > 0
    pill:SetVisible(show)
    if not show then return end
    pill.ZCLabel = (M.Unread == 1 and "1 new message" or (M.Unread .. " new messages")) .. " - click to jump"
    local w, h = chat:GetSize()
    local wide = math.min(PILL_WIDE, math.max(60, w - 8))
    local entry = IsValid(chat.entry) and chat.entry:GetParent()
    local lift = (IsValid(entry) and entry:GetTall() or 20) + 26
    pill:SetSize(wide, 18)
    pill:SetPos((w - wide) * 0.5, math.max(0, h - lift))
end

-- Tab completes "@par" into "@Partner ", and a second Tab cycles the matches.
-- Only after an "@": swallowing every Tab would be a surprise, and the entry
-- has its own uses for the key.
function M.Complete(entry)
    if not IsValid(entry) then return false end
    local text = entry:GetText()
    if type(text) ~= "string" then return false end
    -- On a cycle the text is our own last completion, whose trailing space
    -- would end a backwards scan before it ever reached the "@".
    local cycling = M.CompleteText == text
    local at
    do
        -- The last "@" in the line, spaces and all. Stopping at a space would
        -- make every nickname containing one impossible to complete, and an
        -- over-long stem costs nothing: it simply matches nobody.
        for i = #text, 1, -1 do
            if text:sub(i, i) == "@" then at = i break end
        end
    end
    if not at then return false end
    local stem = text:sub(at + 1)
    if cycling and M.CompleteStem then stem = M.CompleteStem end
    local lower = stem:lower()
    local matches = {}
    for _, known in ipairs(M.NickList()) do
        if known.lower:sub(1, #lower) == lower then matches[#matches + 1] = known.nick end
    end
    if #matches == 0 then return false end
    table.sort(matches)
    local index = cycling and (((M.CompleteIndex or 0) % #matches) + 1) or 1
    local filled = text:sub(1, at) .. matches[index] .. " "
    entry:SetText(filled)
    if entry:GetText() ~= filled then return false end
    entry:SetCaretPos(#filled)
    M.CompleteText, M.CompleteStem, M.CompleteIndex = filled, stem, index
    return true
end

function M.InstallComplete(chat)
    if ZCChatAssist then
        ZCChatAssist.Attach(IsValid(chat) and chat.entry, function() return IsValid(chat) and chat.ZCThreadKey == "main" end)
        return
    end
    local entry = IsValid(chat) and chat.entry
    if not IsValid(entry) or entry.ZCComplete then return end
    entry.ZCComplete = true
    -- rawget, not the plain read: an entry with no handler of its own would
    -- otherwise "restore" to the class function copied onto the instance.
    M.CompleteEntry = entry
    M.CompleteOwn = rawget(entry:GetTable(), "OnKeyCodeTyped")
    local base = entry.OnKeyCodeTyped
    entry.OnKeyCodeTyped = function(self, key, ...)
        if key == KEY_TAB and M.Complete(self) then return true end
        if base then return base(self, key, ...) end
    end
end

-- Called on the OUTGOING module when client.lua is re-included. The chatbox
-- panel outlives the reload, so anything this module hung on it has to come
-- back off - otherwise it keeps running against a module nothing updates.
function M.Uninstall()
    -- The fullscreen view is a popup that outlives a re-include: the incoming
    -- module starts with M.Expanded nil and could never close it again.
    if IsValid(M.Expanded) then M.Expanded:Remove() end
    M.Expanded = nil
    local chat = hg and hg.chat
    if IsValid(chat) and IsValid(chat.ZCUnread) then
        chat.ZCUnread:Remove()
        chat.ZCUnread = nil
    end
    local entry = M.CompleteEntry
    if IsValid(entry) and entry.ZCComplete then
        entry.OnKeyCodeTyped = M.CompleteOwn
        entry.ZCComplete = nil
    end
    M.CompleteEntry, M.CompleteOwn = nil, nil
end

-- Media depth. A large view for any embed, spoiler tokens, and the picker's
-- search and recents. The expand overlay and the reveal button are ordinary
-- child panels of the row: nothing here changes how a row paints, because the
-- paint path runs for every line of chat and a fault there takes all of it out.

local SPOILER_COLOR = Color(158, 155, 155)
local RECENT_FILE = "zc_chat_media_v1/recent.txt"
local RECENT_CAP = 12

M.Spoilers = setmetatable({}, {__mode = "k"})
M.SpoiledURLs = setmetatable({}, {__mode = "k"})
M.Recent = {}

-- One reparse, done the way PerformLayout does it. The panel's own SetMarkup
-- restarts the fade timer and replays the drop-in animation, so an old row
-- rewritten through it pops back to life beside new chat.
function M.Reparse(row, text)
    if not IsValid(row) or type(text) ~= "string" then return false end
    if not (hg and hg.markup and isfunction(hg.markup.Parse)) then return false end
    row.text = text
    if row.BuildMarkup then
        row:BuildMarkup(row:GetWide())
    else
        local draw = row.markup and row.markup.onDrawText
        row.markup = hg.markup.Parse(text, row:GetWide())
        if draw then row.markup.onDrawText = draw end
    end
    row:SetTall(M.TextHeight(row))
    M.Layout(row)
    return true
end

-- ||secret|| becomes a token. Not a blur: markup draws text and has no blur to
-- ask for, and a block-character mask would depend on a glyph in a font this
-- cannot check. A token is unmistakable, renders anywhere, and reverses exactly.
function M.MaskSpoilers(value, state)
    if type(value) ~= "string" or not value:find("||", 1, true) then return value end
    -- Anything already spelled like a token is spaced apart first, so the token
    -- about to be written is the only one of its kind in the line. Otherwise
    -- "[spoiler 1] ||secret||" puts two identical tokens in the row, and
    -- revealing fills in the decoy while the real one stays shut for good.
    value = value:gsub("%[spoiler ", "[ spoiler ")
    -- Bars that nest or run together pair off left to right, which can leave a
    -- middle segment outside every pair. For text that is a fair reading of
    -- ambiguous input. For a link it is not: suppress every link between the
    -- first and the last bar from embedding, masked or not.
    local first = value:find("||", 1, true)
    local last, scan = nil, first
    while true do
        local at = value:find("||", scan, true)
        if not at then break end
        last, scan = at, at + 2
    end
    if last and last > first then
        for link in value:sub(first, last + 1):gmatch("https://[^%s<>\"']+") do
            state.urls[(link:gsub("[%)%],!;%.]+$", ""))] = true
        end
    end
    return (value:gsub("||(.-)||", function(secret)
        if secret == "" then return "||||" end
        state.count = state.count + 1
        local token = "[spoiler " .. state.count .. "]"
        state.list[#state.list + 1] = {token = token, text = secret}
        for link in secret:gmatch("https://[^%s<>\"']+") do
            state.urls[(link:gsub("[%)%],!;%.]+$", ""))] = true
        end
        return token
    end))
end

function M.RevealRow(row)
    if not IsValid(row) or not row.ZCSpoilers or row.ZCRevealed then return false end
    local text = row.text
    if type(text) ~= "string" then return false end
    for _, item in ipairs(row.ZCSpoilers) do
        -- Escaped and emoji-expanded exactly as AddLine would have done it.
        local replacement = (M.Format(item.text, 18):gsub("%%", "%%%%"))
        text = text:gsub(M.Pattern(item.token), replacement, 1)
        for _, key in ipairs({"ZCFullText", "ZCGroupedText", "ZCFullOriginal", "ZCGroupedOriginal"}) do
            if row[key] then row[key] = row[key]:gsub(M.Pattern(item.token), replacement, 1) end
        end
    end
    row.ZCRevealed = true
    if IsValid(row.ZCReveal) then row.ZCReveal:Remove(); row.ZCReveal = nil end
    M.Reparse(row, text)
    return true
end

function M.Pattern(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

function M.AttachSpoilers(row, elements)
    local list = M.Spoilers[elements]
    if not list or #list == 0 or not IsValid(row) then return end
    row.ZCSpoilers = list
    local button = vgui.Create("DButton", row)
    row.ZCReveal = button
    button:SetText("")
    button:SetSize(54, 14)
    button.Paint = function(self, w, h)
        surface.SetDrawColor(46, 43, 43, 220)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("reveal", "zChatFontSmall", w * 0.5, h * 0.5,
            SPOILER_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    button.DoClick = function() M.RevealRow(row) end
    M.Layout(row)
end

-- A transparent hit area laid over the embed. The browser underneath keeps
-- mouse input off, so this is the only thing a click can land on.
function M.AttachExpand(row)
    if not IsValid(row) or IsValid(row.ZCExpandHit) then return end
    local hit = vgui.Create("DButton", row)
    row.ZCExpandHit = hit
    hit:SetText("")
    hit:SetCursor("hand")
    hit.Paint = function() end
    hit.DoClick = function() M.Expand(row) end
end

function M.Expand(row)
    if not M.InlineEnabled() then return end
    if not IsValid(row) then return false end
    local html = M.HTML(row.ZCGifURL)
    if not html then return false end
    if IsValid(M.Expanded) then M.Expanded:Remove() end
    local frame = vgui.Create("DFrame")
    if not IsValid(frame) then return false end
    M.Expanded = frame
    frame.ZCMessageID = row.ZCMessageID
    frame:SetTitle(""); frame:ShowCloseButton(false)
    frame:SetDraggable(false); frame:SetSizable(false)
    frame:SetSize(ScrW(), ScrH()); frame:SetPos(0, 0); frame:MakePopup()
    frame.Paint = function(_, width, height)
        surface.SetDrawColor(0, 0, 0, 240)
        surface.DrawRect(0, 0, width, height)
    end
    frame.OnRemove = function() if M.Expanded == frame then M.Expanded = nil end end
    -- A new browser, not the row's. An image has no playback state worth
    -- carrying over, and moving the live one would leave the row empty if this
    -- frame outlived it - which the video player has to handle and this need not.
    local view = vgui.Create("DHTML", frame)
    if not IsValid(view) then frame:Remove(); return false end
    local wide = math.floor(math.min(ScrW() * 0.8, ScrH() * 0.8 * 1.4))
    local tall = math.floor(ScrH() * 0.8)
    view:SetSize(wide, tall)
    view:SetPos(math.floor((ScrW() - wide) * 0.5), math.floor((ScrH() - tall) * 0.5))
    view:SetAllowLua(false)
    view:SetMouseInputEnabled(false); view:SetKeyboardInputEnabled(false)
    view:SetHTML(html)
    local close = vgui.Create("DButton", frame)
    close:SetSize(96, 26); close:SetPos(ScrW() - 108, 12); close:SetText("Close")
    close.DoClick = function() frame:Remove() end
    return true
end

function M.LoadRecent()
    M.Recent = {}
    local body = file.Read(RECENT_FILE, "DATA")
    if type(body) ~= "string" then return end
    for line in body:gmatch("[^\r\n]+") do
        if M.Emojis[line] then
            local seen = false
            for _, name in ipairs(M.Recent) do if name == line then seen = true break end end
            if not seen then
                M.Recent[#M.Recent + 1] = line
                if #M.Recent >= RECENT_CAP then break end
            end
        end
    end
end

function M.NoteRecent(name)
    if not M.Emojis[name] then return false end
    for index, value in ipairs(M.Recent) do
        if value == name then table.remove(M.Recent, index) break end
    end
    table.insert(M.Recent, 1, name)
    for index = #M.Recent, RECENT_CAP + 1, -1 do M.Recent[index] = nil end
    file.Write(RECENT_FILE, table.concat(M.Recent, "\n"))
    return true
end

-- Name first, then aliases, so ":fire:" is never buried under everything that
-- merely mentions fire. An empty query matches every name and so returns the
-- whole set in its authored order, which is what the picker opens on.
function M.SearchEmojis(query)
    query = tostring(query or ""):lower():gsub("^[%s:]+", ""):gsub("[%s:]+$", "")
    local prefix, loose = {}, {}
    for _, name in ipairs(M.Order) do
        local alias = M.Aliases[name] or ""
        if name:sub(1, #query) == query then prefix[#prefix + 1] = name
        elseif name:find(query, 1, true) or (" " .. alias .. " "):find(" " .. query, 1, true) then
            loose[#loose + 1] = name
        end
    end
    local out = {}
    for _, list in ipairs({prefix, loose}) do
        for _, name in ipairs(list) do out[#out + 1] = name end
    end
    return out
end

-- Media moderation. Three controls share one decision: a speaker you muted, a
-- speaker staff purged, and a speaker posting embeds faster than anyone wants
-- to read them all lose the embed and keep the link as readable text. None of
-- this is authority - it is presentation, decided and enforced on this client.
local HIDDEN_FILE = "zc_chat_media_v1/hidden.txt"
local HIDDEN_CAP = 100
local FLOOD_LIMIT, FLOOD_WINDOW = 3, 45
local PURGE_DEFAULT = 600
M.Hidden = {}
M.Purged = previous and previous.Purged or {}
M.MediaLog = previous and previous.MediaLog or {}
M.Verdicts = setmetatable({}, {__mode = "k"})

local VERDICT_NOTE = {
    hidden = "  (media hidden)",
    purged = "  (media removed by staff)",
    flood = "  (media hidden - too many at once)",
}

function M.LoadHidden()
    M.Hidden = {}
    local body = file.Read(HIDDEN_FILE, "DATA")
    if type(body) ~= "string" then return end
    local count = 0
    for line in body:gmatch("[^\r\n]+") do
        if #line <= 20 and line:match("^%d+$") and not M.Hidden[line] then
            M.Hidden[line] = true
            count = count + 1
            if count >= HIDDEN_CAP then break end
        end
    end
end

function M.SaveHidden()
    local lines = {}
    for steam in pairs(M.Hidden) do lines[#lines + 1] = steam end
    table.sort(lines)
    file.Write(HIDDEN_FILE, table.concat(lines, "\n"))
end

function M.HiddenCount()
    local count = 0
    for _ in pairs(M.Hidden) do count = count + 1 end
    return count
end

function M.IsHidden(steam)
    return M.Hidden[steam] == true
end

function M.SetHidden(steam, hidden)
    if type(steam) ~= "string" or not steam:match("^%d+$") then return false end
    if hidden then
        if M.Hidden[steam] then return true end
        -- Hiding yourself looks exactly like the feature being broken.
        local me = LocalPlayer and LocalPlayer()
        if IsValid(me) and me:SteamID64() == steam then
            notification.AddLegacy("That is you.", NOTIFY_ERROR, 4)
            return false
        end
        if M.HiddenCount() >= HIDDEN_CAP then
            notification.AddLegacy("Hidden list is full (" .. HIDDEN_CAP .. ").", NOTIFY_ERROR, 5)
            return false
        end
    end
    M.Hidden[steam] = hidden or nil
    M.SaveHidden()
    return true
end

function M.IsPurged(steam)
    local expiry = M.Purged[steam]
    if not expiry then return false end
    if RealTime() >= expiry then M.Purged[steam] = nil; return false end
    return true
end

-- The log is keyed by speaker, so it is swept whole rather than left to grow a
-- row per player who ever posted a link this map.
function M.SpendMedia(steam)
    local now = RealTime()
    for id, log in pairs(M.MediaLog) do
        if (log[#log] or 0) <= now - FLOOD_WINDOW then M.MediaLog[id] = nil end
    end
    local log = M.MediaLog[steam]
    if not log then log = {}; M.MediaLog[steam] = log end
    local kept = 0
    for i = 1, #log do
        if log[i] > now - FLOOD_WINDOW then kept = kept + 1; log[kept] = log[i] end
    end
    for i = #log, kept + 1, -1 do log[i] = nil end
    if kept >= FLOOD_LIMIT then return false end
    log[kept + 1] = now
    return true
end

-- "allow", "hidden", "purged" or "flood". Decided once per message and
-- remembered against the elements table: DisplayElements and Attach both ask,
-- and they must agree without charging the flood budget twice. Only called once
-- a message is known to carry media, so a chatty player with no links never
-- spends any of it.
function M.Verdict(elements)
    if type(elements) ~= "table" then return "allow" end
    local cached = M.Verdicts[elements]
    if cached then return cached end
    local verdict = "allow"
    local speaker = M.ReportSpeaker(elements)
    local steam = speaker and speaker:SteamID64()
    if type(steam) == "string" and steam:match("^%d+$") then
        if M.IsHidden(steam) then verdict = "hidden"
        elseif M.IsPurged(steam) then verdict = "purged"
        elseif not M.Restoring and not M.SpendMedia(steam) then verdict = "flood" end
    end
    M.Verdicts[elements] = verdict
    return verdict
end

function M.VerdictNote(verdict)
    return VERDICT_NOTE[verdict]
end

-- Take the embed off a row that already has one, leaving the message and its
-- report flag in place. The stashed original text carries the link, so the row
-- ends up reading the way a suppressed one would have in the first place.
function M.StripMedia(row)
    if not IsValid(row) then return false end
    if not row.ZCGifURL and not row.ZCVideoID then return false end
    row.ZCHasInlineMedia = nil
    M.Release(row)
    if IsValid(row.ZCGifPlaceholder) then row.ZCGifPlaceholder:Remove() end
    if IsValid(row.ZCExpandHit) then row.ZCExpandHit:Remove() end
    if IsValid(row.ZCVideoCard) then row.ZCVideoCard:Remove() end
    if row.OnRemove == row.ZCGifRemove then row.OnRemove = row.ZCGifPreviousRemove end
    row.ZCExpandHit = nil
    row.ZCGifPlaceholder = nil; row.ZCGifURL = nil
    row.ZCVideoCard = nil; row.ZCVideoID = nil; row.ZCVideoStart = nil
    row.ZCGifRemove = nil; row.ZCGifPreviousRemove = nil
    M.Rows[row] = nil
    row.ZCFullText = row.ZCFullOriginal or row.ZCFullText
    row.ZCGroupedText = row.ZCGroupedOriginal or row.ZCGroupedText
    local original = (row.ZCGrouped and row.ZCGroupedOriginal or row.ZCFullOriginal) or row.ZCGifOriginalText
    row.ZCGifOriginalText = nil
    -- AddLine stashed that text before the social pass ran, so it still spells
    -- out anything the author put behind bars. Putting it back unmasked would
    -- mean "hide this player's media" and a staff purge both PUBLISH a secret.
    -- Re-masking regenerates the same tokens in the same order, so the reveal
    -- button on this row keeps working.
    if type(original) == "string" and row.ZCSpoilers and not row.ZCRevealed then
        original = M.MaskSpoilers(original, {count = 0, list = {}, urls = {}})
    end
    -- Put the link back the way PerformLayout would, and no further. The
    -- panel's own SetMarkup is not a plain setter: it also restarts the fade
    -- timer and replays the drop-in animation, so restoring a long-faded
    -- message through it would make it pop back to life beside new chat.
    if not M.Reparse(row, original) then
        if row.markup then row:SetTall(M.TextHeight(row)) end
        M.Layout(row)
    end
    return true
end

function M.StripSpeaker(steam)
    local removed = 0
    for row in pairs(M.Rows) do
        if IsValid(row) and row.ZCReport and row.ZCReport.steam == steam then
            if M.StripMedia(row) then removed = removed + 1 end
        end
    end
    return removed
end

-- Staff wiped a player's media: existing embeds come down and new ones stay as
-- plain links for a while, so the next message does not simply undo the purge.
function M.PurgeSpeaker(steam, seconds)
    if type(steam) ~= "string" or not steam:match("^%d+$") then return 0 end
    seconds = math.Clamp(math.floor(tonumber(seconds) or PURGE_DEFAULT), 0, 3600)
    if seconds > 0 then M.Purged[steam] = RealTime() + seconds end
    return M.StripSpeaker(steam)
end

net.Receive("zcChatMediaPurge", function()
    local steam = net.ReadString()
    local seconds = net.ReadUInt(16)
    if M.PurgeSpeaker(steam, seconds) > 0 then
        notification.AddLegacy("Staff removed chat media from a player.", NOTIFY_CLEANUP, 4)
    end
end)

concommand.Add("zc_chat_media_hidden", function(_, _, args)
    local action = string.lower(tostring(args and args[1] or "list"))
    if action == "clear" then
        M.Hidden = {}; M.SaveHidden()
        print("[ChatMedia] hidden list cleared")
        return
    end
    local ids = {}
    for steam in pairs(M.Hidden) do ids[#ids + 1] = steam end
    table.sort(ids)
    print(string.format("[ChatMedia] %d hidden player(s); zc_chat_media_hidden clear empties the list", #ids))
    for _, steam in ipairs(ids) do print("  " .. steam) end
end, nil, "List players whose chat media you hid; zc_chat_media_hidden clear empties the list.")

-- A re-include finds the chatbox already built and InstallButton long since
-- called, so the pill and the Tab hook have to be put back by hand. On a first
-- load hg.chat does not exist yet and PANEL:Init does it the usual way.
if hg and IsValid(hg.chat) then
    M.InstallPill(hg.chat)
    M.InstallComplete(hg.chat)
end

M.LoadHidden()
M.LoadRecent()

-- Reporting. Every message a player spoke carries a quiet flag in its corner;
-- the reasons here must stay in step with the server file's REASONS list.
M.ReportReasons = {
    "Inappropriate media",
    "Harassment or slurs",
    "Spam or flooding",
    "Something else",
}
local REPORT_COOLDOWN = 20

function M.ReportSpeaker(elements)
    if IsValid(CHAT_SPEAKER) and CHAT_SPEAKER:IsPlayer() then return CHAT_SPEAKER end
    for _, value in ipairs(elements) do
        if type(value) == "Player" and IsValid(value) then return value end
    end
end

function M.PlainText(elements)
    local parts = {}
    for _, value in ipairs(elements) do
        if type(value) == "string" then parts[#parts + 1] = value end
    end
    return table.concat(parts, " ")
end

function M.SendReport(row, reason)
    local data = IsValid(row) and row.ZCReport
    if not data or not M.ReportReasons[reason] then return false end
    if RealTime() < (M.NextReport or 0) then
        notification.AddLegacy("Wait a moment before reporting again.", NOTIFY_ERROR, 4)
        return false
    end
    -- If the server half has not loaded yet the message is unregistered, which
    -- throws; say something useful instead of erroring in the player's face.
    local sent = pcall(function()
        net.Start("zcChatReport")
            net.WriteString(data.steam)
            net.WriteString(data.name)
            net.WriteUInt(reason, 4)
            net.WriteString(data.text)
            net.WriteString(data.media)
        net.SendToServer()
    end)
    if not sent then
        notification.AddLegacy("Reporting is not available yet - tell staff directly.", NOTIFY_ERROR, 5)
        return false
    end
    M.NextReport = RealTime() + REPORT_COOLDOWN
    notification.AddLegacy("Report sent to staff.", NOTIFY_GENERIC, 4)
    surface.PlaySound("buttons/button15.wav")
    return true
end

function M.OpenReportMenu(row)
    if not IsValid(row) or not row.ZCReport then return end
    local menu = DermaMenu()
    if not IsValid(menu) then return end
    M.ReportMenu = menu
    for index, reason in ipairs(M.ReportReasons) do
        menu:AddOption(reason, function() M.SendReport(row, index) end)
    end
    menu:AddSpacer()
    local steam = row.ZCReport.steam
    if M.IsHidden(steam) then
        menu:AddOption("Show this player's media", function()
            if M.SetHidden(steam, false) then
                notification.AddLegacy("Their media will show again.", NOTIFY_GENERIC, 4)
            end
        end)
    else
        menu:AddOption("Hide this player's media", function()
            if not M.SetHidden(steam, true) then return end
            M.StripSpeaker(steam)
            notification.AddLegacy("Media from " .. (row.ZCReport.name ~= "" and row.ZCReport.name or steam)
                .. " is hidden for you.", NOTIFY_GENERIC, 5)
        end)
    end
    menu:AddSpacer()
    menu:AddOption("Cancel", function() end)
    menu:Open()
end

function M.ReportPaint(button, width, height)
    local hot = button:IsHovered()
    local shade = hot and 235 or 150
    surface.SetDrawColor(shade, hot and 80 or 150, hot and 80 or 150, hot and 255 or 170)
    surface.DrawRect(3, 2, 2, height - 4)
    draw.NoTexture()
    surface.DrawPoly({
        {x = 5, y = 3},
        {x = width - 3, y = 6},
        {x = 5, y = 9},
    })
end

function M.AttachReport(row, elements)
    if row.ZCReport then return end
    local speaker = M.ReportSpeaker(elements)
    if not speaker then return end
    if speaker == LocalPlayer() or speaker:IsBot() then return end
    local steam = speaker:SteamID64()
    if type(steam) ~= "string" or not steam:match("^%d+$") then return end

    row.ZCReport = {
        steam = steam,
        name = string.sub(tostring(speaker:Nick() or ""), 1, 64),
        text = string.sub(M.PlainText(elements), 1, 200),
        media = "",
    }

    local button = vgui.Create("DButton", row)
    if not IsValid(button) then return end
    row.ZCReportButton = button
    button:SetText("")
    button:SetKeyboardInputEnabled(false)
    button:SetTooltip("Report this message")
    button:SetVisible(false)
    button.Paint = function(panel, w, h)
        local alpha = M.Alpha(row)
        draw.RoundedBox(0, 0, 0, w, h, Color(92, 89, 89, alpha * (panel:IsHovered() and 0.85 or 0.58)))
        surface.SetDrawColor(225, 222, 222, alpha)
        surface.DrawRect(7, 5, 1, 13)
        draw.NoTexture()
        surface.DrawPoly({{x=8,y=5},{x=18,y=7},{x=8,y=11}})
    end
    button.DoClick = function() M.OpenReportMenu(row) end
    -- The row needs mouse input for the hover test; a bare Panel does not handle
    -- the wheel, so the scroll panel still scrolls through it.
    row:SetMouseInputEnabled(true)
end

-- Driven by the chat root: hidden child panels do not receive Think.
function M.UpdateRowActions(row, chat)
    local open = IsValid(chat) and ZCChatThreads.Visible(row) and not IsValid(chat.ZCDirectory) and chat:GetActive() and chat.phonePage == "chat" and not IsValid(M.Picker)
    local inspecting=ZCChatGroupUI and ZCChatGroupUI.meta[row.ZCConversation] and ZCChatGroupUI.meta[row.ZCConversation].peek
    if IsValid(row.ZCReactionAdd) then
        local panel = row.ZCReactionAdd
        panel.ZCBlend = Lerp(math.Clamp(FrameTime() * 18, 0, 1), panel.ZCBlend or 0, open and 1 or 0)
        panel:SetVisible(not inspecting and (open or panel.ZCBlend > 0.01))
        panel:SetMouseInputEnabled(open and not inspecting)
    end
    if IsValid(row.ZCReportButton) then
        row.ZCReportButton:SetVisible(open)
    end
    if IsValid(row.ZCModerationButton) then
        row.ZCModerationButton:SetVisible(open and LocalPlayer():GetNWBool("ZCChatCanDelete", false))
    end
end

function M.ReactionAddPaint(panel, w, h)
    local row = panel:GetParent()
    local hover = panel:IsHovered() or row:IsHovered()
    panel.ZCHover = Lerp(math.Clamp(FrameTime() * 16, 0, 1), panel.ZCHover or 0, hover and 1 or 0)
    local alpha = M.Alpha(row) * (panel.ZCBlend or 0)
    local shade = row.ZCOwn and Color(150, 0, 0, alpha * (0.58 + panel.ZCHover * 0.25))
        or Color(92, 89, 89, alpha * (0.58 + panel.ZCHover * 0.25))
    draw.RoundedBox(0, 0, 0, w, h, shade)
    draw.SimpleText("+", "DermaDefaultBold", w / 2, h / 2, Color(235, 232, 232, alpha * (0.65 + panel.ZCHover * 0.35)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function M.LayoutReport(row)
    if not IsValid(row.ZCReportButton) then return end
    row.ZCReportButton:SetSize(24, 24)
    local bubbleX = row.ZCBubbleX or 0
    local bubbleWidth = row.ZCBubbleWidth or row:GetWide()
    local x = row.ZCOwn and math.max(0, bubbleX - 48)
        or math.min(row:GetWide() - 24, bubbleX + bubbleWidth + 24)
    row.ZCReportButton:SetPos(x, math.max(0, (row.ZCBubbleBodyHeight or 42) - 24))
end

M.DeletedIDs = previous and previous.DeletedIDs or {}
M.DeletedOrder = previous and previous.DeletedOrder or {}
function M.DeleteMessage(id)
    if not M.DeletedIDs[id] then
        M.DeletedIDs[id] = true; M.DeletedOrder[#M.DeletedOrder+1] = id
        while #M.DeletedOrder > 1024 do M.DeletedIDs[table.remove(M.DeletedOrder,1)] = nil end
    end
    if IsValid(M.Expanded) and M.Expanded.ZCMessageID == id then M.Expanded:Remove(); M.Expanded=nil end
    if IsValid(M.VideoRow) and M.VideoRow.ZCMessageID == id then M.StopVideo() end
    local chat = hg and hg.chat
    if IsValid(chat) then
        ZCChatThreads.ForEach(chat,function(state)
            for i=#state.entries,1,-1 do
                local row=state.entries[i]
                if IsValid(row) and row.ZCMessageID==id then M.Release(row);table.remove(state.entries,i);row:Remove() end
            end
            if chat.ZCThreads then ZCChatThreads.WithState(chat,state,function() M.ReflowChains(chat) end)
            else M.ReflowChains(chat) end
            state.history:InvalidateLayout(true)
        end)
    end
    M.ReactionRows[id]=nil
end
net.Receive("zcChatDeleted",function() M.DeleteMessage(net.ReadUInt(32)) end)
net.Receive("zcChatDeleteResult",function()
    local ok,detail=net.ReadBool(),net.ReadString()
    if hg and IsValid(hg.chat) and hg.chat.ShowSystemBanner then hg.chat:ShowSystemBanner({detail}) end
end)
function M.AttachModeration(row)
    if not row.ZCBubble or not row.ZCMessageID or row.ZCMessageID==0 then return end
    local button=vgui.Create("DButton",row)
    row.ZCModerationButton=button
    button:SetSize(24,24); button:SetText(""); button:SetVisible(false)
    button:SetKeyboardInputEnabled(false); button:SetTooltip("Moderate this message")
    button.Paint=function(panel,w,h)
        local alpha=M.Alpha(row)
        draw.RoundedBox(0,0,0,w,h,Color(96,67,88,alpha*(panel:IsHovered() and .9 or .6)))
        draw.SimpleText("···","DermaDefaultBold",w/2,h/2,Color(244,213,226,alpha),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    end
    button.DoClick=function()
        if not LocalPlayer():GetNWBool("ZCChatCanDelete",false) then return end
        local menu=DermaMenu()
        menu:AddOption("Delete message and media",function()
            if not IsValid(row) then return end
            net.Start("zcChatDelete"); net.WriteUInt(row.ZCMessageID,32); net.SendToServer()
        end)
        menu:Open()
    end
end
function M.LayoutModeration(row)
    if not IsValid(row.ZCModerationButton) then return end
    local x=row.ZCOwn and math.max(0,(row.ZCBubbleX or 0)-50)
        or math.min(row:GetWide()-24,(row.ZCBubbleX or 0)+(row.ZCBubbleWidth or 0)+(IsValid(row.ZCReportButton) and 50 or 24))
    row.ZCModerationButton:SetPos(x,math.max(0,(row.ZCBubbleBodyHeight or 42)-24))
end

M.ReactionNames = {"thumbsup", "heart", "laugh", "cry", "fire", "skull"}
M.ReactionLabels = {"Like", "Love", "Laugh", "Sad", "Fire", "Skull"}
M.ReactionRows = setmetatable({}, {__mode = "v"})

function M.SendReaction(row, index)
    if not IsValid(row) or not row.ZCMessageID or not M.ReactionNames[index] then return end
    net.Start("zcChatReact")
        net.WriteUInt(row.ZCMessageID, 32)
        net.WriteUInt(index, 3)
    net.SendToServer()
end

function M.OpenReactionMenu(row)
    if not IsValid(row) or not row.ZCMessageID then return end
    local menu = DermaMenu()
    if not IsValid(menu) then return end
    menu:AddOption("Reply", function() M.BeginReply(row) end)
    menu:AddOption("Mention sender", function() M.MentionSender(row) end)
    menu:AddSpacer()
    for index, label in ipairs(M.ReactionLabels) do
        local option = menu:AddOption(label, function() M.SendReaction(row, index) end)
        local emoji = M.Emojis[M.ReactionNames[index]]
        if emoji and option.SetIcon then option:SetIcon(emoji.path) end
    end
    menu:Open()
end

function M.AttachReaction(row)
    if not row.ZCBubble or not row.ZCMessageID or row.ZCMessageID == 0 then return end
    M.ReactionRows[row.ZCMessageID] = row
    row.ZCReactionCounts = {0, 0, 0, 0, 0, 0}
    row.ZCReactionButtons = {}
    local add = vgui.Create("DButton", row)
    row.ZCReactionAdd = add
    add:SetText(""); add:SetSize(26, 24)
    add.Paint = M.ReactionAddPaint
    add:SetTooltip("React or reply to this message")
    add:SetKeyboardInputEnabled(false)
    add.DoClick = function() M.OpenReactionMenu(row) end
    add:SetVisible(false)
    row:SetMouseInputEnabled(true)
    for index, name in ipairs(M.ReactionNames) do
        local pill = vgui.Create("DButton", row)
        row.ZCReactionButtons[index] = pill
        pill:SetText(""); pill:SetSize(36, 18); pill:SetVisible(false)
        pill:SetKeyboardInputEnabled(false)
        pill.DoClick = function() M.SendReaction(row, index) end
        pill.Paint = function(_, w, h)
            local alpha = M.Alpha(row)
            local selected = row.ZCReactionSelected == index
            draw.RoundedBox(0, 0, 0, w, h, selected and Color(150, 0, 0, alpha * 0.8)
                or Color(83, 80, 80, alpha * 0.65))
            local emoji = M.Emojis[name]
            if emoji then
                surface.SetDrawColor(255, 255, 255, alpha)
                surface.SetMaterial(emoji.material)
                surface.DrawTexturedRect(3, 1, 16, 16)
            end
            draw.SimpleText(tostring(row.ZCReactionCounts[index] or 0), "DermaDefault", 21, 2,
                Color(244, 241, 241, alpha), TEXT_ALIGN_LEFT)
        end
    end
    M.LayoutReaction(row)
end

function M.LayoutReaction(row)
    if not IsValid(row.ZCReactionAdd) then return end
    local bubbleX = row.ZCBubbleX or 0
    local bubbleWidth = row.ZCBubbleWidth or row:GetWide()
    local addX = row.ZCOwn and math.max(0, bubbleX - 22)
        or math.min(row:GetWide() - 26, bubbleX + bubbleWidth - 4)
    row.ZCReactionAdd:SetPos(addX, math.max(0, (row.ZCBubbleBodyHeight or 42) - 24))
    local countShown = 0
    for _, count in ipairs(row.ZCReactionCounts or {}) do if count > 0 then countShown = countShown + 1 end end
    local startX = row.ZCOwn and math.max(0, bubbleX + bubbleWidth - countShown * 38)
        or math.min(bubbleX + 4, row:GetWide() - countShown * 38)
    local shown = 0
    for index, pill in ipairs(row.ZCReactionButtons or {}) do
        local count = row.ZCReactionCounts[index] or 0
        pill:SetVisible(count > 0)
        if count > 0 then
            local x = startX + shown * 38
            pill:SetPos(x, row.ZCBubbleBodyHeight + 1)
            shown = shown + 1
        end
    end
end

net.Receive("zcChatReactionState", function()
    local id = net.ReadUInt(32)
    local counts = {}
    local total = 0
    for i = 1, 6 do counts[i] = net.ReadUInt(8); total = total + counts[i] end
    local reactor = net.ReadString()
    local selected = net.ReadUInt(3)
    local row = M.ReactionRows[id]
    if not IsValid(row) then return end
    row.ZCReactionCounts = counts
    row.ZCReactionsVisible = total > 0
    if reactor == LocalPlayer():SteamID64() then row.ZCReactionSelected = selected end
    if row.BuildMarkup then row:BuildMarkup(row:GetWide()) end
    row:SetTall(M.TextHeight(row))
    M.Layout(row)
    row:InvalidateParent(true)
end)

function M.Release(row)
    M.Stop(row)
    if M.VideoRow == row then M.StopVideo() end
end

function M.OwnRow(row)
    M.Serial = (M.Serial or 0) + 1
    M.Rows[row] = M.Serial
    local previousRemove = row.OnRemove
    row.ZCGifPreviousRemove = previousRemove
    row.ZCGifRemove = function(self)
        M.Release(self); M.Rows[self] = nil
        if previousRemove then previousRemove(self) end
    end
    row.OnRemove = row.ZCGifRemove
end

function M.Attach(row, elements)
    if M.Rows[row] then return end
    M.AttachSocial(row, elements)
    M.AttachReport(row, elements)
    M.AttachReaction(row)
    M.AttachModeration(row)
    M.AttachReply(row)
    local kind, first, start = M.FindMedia(elements)
    if row.ZCReport then
        row.ZCReport.media = (kind == "gif" and first)
            or (kind == "video" and ("https://youtu.be/" .. first)) or ""
    end
    M.AttachSpoilers(row, elements)
    -- Same verdict DisplayElements already reached for this message.
    if kind and M.Verdict(elements) ~= "allow" then return end
    -- A link inside a spoiler stays a link: DisplayElements never saw it, so
    -- embedding it here would show the picture the spoiler was hiding.
    local spoiled = M.SpoiledURLs[elements]
    if kind and spoiled and spoiled[first] then return end
    if kind == "gif" then
        row.ZCGifURL = first
        M.OwnRow(row)
        local placeholder = vgui.Create("DLabel", row)
        row.ZCGifPlaceholder = placeholder
        placeholder:SetMouseInputEnabled(false); placeholder:SetKeyboardInputEnabled(false)
        M.AttachExpand(row)
        M.Layout(row)
    elseif kind == "video" and M.AttachVideo(row, first, start) then
        M.OwnRow(row)
        M.Layout(row)
    end
end

function M.Detach(row)
    row.ZCHasInlineMedia = nil
    M.Release(row)
    if IsValid(row.ZCReportButton) then row.ZCReportButton:Remove() end
    row.ZCReportButton = nil; row.ZCReport = nil
    if row.ZCMessageID then M.ReactionRows[row.ZCMessageID] = nil end
    if IsValid(row.ZCReactionAdd) then row.ZCReactionAdd:Remove() end
    for _, pill in ipairs(row.ZCReactionButtons or {}) do if IsValid(pill) then pill:Remove() end end
    row.ZCReactionAdd = nil; row.ZCReactionButtons = nil
    if IsValid(row.ZCGifPlaceholder) then row.ZCGifPlaceholder:Remove() end
    if IsValid(row.ZCExpandHit) then row.ZCExpandHit:Remove() end
    if IsValid(row.ZCReveal) then row.ZCReveal:Remove() end
    if IsValid(row.ZCVideoCard) then row.ZCVideoCard:Remove() end
    if row.OnRemove == row.ZCGifRemove then row.OnRemove = row.ZCGifPreviousRemove end
    row.ZCExpandHit = nil; row.ZCReveal = nil; row.ZCSpoilers = nil
    row.ZCGifPlaceholder = nil; row.ZCGifURL = nil
    row.ZCVideoCard = nil; row.ZCVideoID = nil; row.ZCVideoStart = nil
    row.ZCGifRemove = nil; row.ZCGifPreviousRemove = nil
    M.Rows[row] = nil
end

function M.ClosePicker()
    if IsValid(M.Picker) then M.Picker:Remove() end
    M.Picker = nil
end

function M.Close()
    M.Stop()
    M.StopVideo()
    M.ClosePicker()
    M.Uninstall()
end

function M.UpdatePlayback()
    if RealTime() < (M.NextUpdate or 0) then return end
    M.NextUpdate = RealTime() + 0.1
    if IsValid(M.Picker) and (not hg or not IsValid(hg.chat) or not hg.chat:GetActive()) then M.ClosePicker() end
    M.UpdateVideo()
    local visible = {}
    for row in pairs(M.Rows) do
        if not IsValid(row) then
            M.Stop(row); M.Rows[row] = nil
        else
            local alpha = M.Alpha(row)
            if IsValid(row.ZCGifPlaceholder) then row.ZCGifPlaceholder:SetAlpha(alpha) end
            if M.Visible(row) then visible[#visible + 1] = row else M.Stop(row) end
        end
    end
    table.sort(visible, function(a, b) return M.Rows[a] > M.Rows[b] end)
    for i = 4, #visible do M.Stop(visible[i]) end
    for i = 1, math.min(3, #visible) do
        local row = visible[i]
        if IsValid(row.ZCGifBrowser) then row.ZCGifBrowser:SetAlpha(M.Alpha(row)) else M.Play(row) end
    end
end

function M.InsertText(entry, token)
    if not IsValid(entry) or type(token) ~= "string" then return false end
    local before = entry:GetText()
    local limit = GetConVar("zchat_maxmessagelength")
    if #before + #token > (limit and limit:GetInt() or 256) then return false end
    -- The native entry's InsertText is a no-op on some mounted UI variants.
    -- Use SetText and keep the cursor on a UTF-8 character boundary.
    local caret = math.max(0, math.floor(entry:GetCaretPos() or 0))
    local offset, position = 1, 0
    while offset <= #before and position < caret do
        offset = offset + 1
        while offset <= #before do
            local byte = before:byte(offset)
            if byte < 128 or byte >= 192 then break end
            offset = offset + 1
        end
        position = position + 1
    end
    local after = before:sub(1, offset - 1) .. token .. before:sub(offset)
    entry:SetText(after)
    if entry:GetText() ~= after then return false end
    entry:SetCaretPos(position + #token)
    entry:RequestFocus()
    return true
end

function M.Insert(entry, name)
    if not M.Emojis[name] then return false end
    return M.InsertText(entry, ":" .. name .. ": ")
end

-- One owned sheet inside GoobOS; search callbacks remain scoped to its body.
function M.PickerButton(parent, text)
    local button = vgui.Create("DButton", parent)
    button:SetText(text)
    button:SetTextColor(Color(235, 232, 232))
    button:SetKeyboardInputEnabled(false)
    button.Paint = function(panel, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(150, 0, 0, panel:IsHovered() and 230 or 125))
    end
    return button
end

function M.CreatePicker(chat, selected)
    if ZCChatThreads then ZCChatThreads.CloseDirectory(chat) end
    M.ClosePicker()
    -- Keep the composer visible and provide enough room for results at small sizes.
    local target = math.min(360, ScrH() - 96)
    if chat:GetTall() < target then
        local x, y = chat:GetPos()
        local bottom = y + chat:GetTall()
        chat:SetTall(target); chat:SetPos(x, bottom - target)
        chat:InvalidateLayout(true)
    end
    local shell = vgui.Create("DPanel", chat)
    M.Picker = shell
    shell.ZCTab = selected
    shell.ZCOpenedAt = RealTime()
    shell.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(32, 29, 29, 252))
    end
    shell.Close = function() M.ClosePicker(); if IsValid(chat) and chat:GetActive() then chat.entry:RequestFocus() end end
    local emoji = M.PickerButton(shell, "Emojis")
    local gifsTab = M.PickerButton(shell, "GIFs")
    local settings = M.PickerButton(shell, "Settings")
    local back = M.PickerButton(shell, "Back")
    emoji:SetPos(8, 8); emoji:SetSize(72, 28)
    gifsTab:SetPos(86, 8); gifsTab:SetSize(64, 28)
    settings:SetPos(156, 8); settings:SetSize(76, 28)
    back:SetSize(52, 28)
    for _, item in ipairs({{emoji,"emoji"},{gifsTab,"gifs"},{settings,"settings"}}) do
        if selected == item[2] then item[1]:SetTextColor(Color(192, 0, 0)) end
    end
    emoji.DoClick = function() M.OpenPicker(chat, "emoji") end
    gifsTab.DoClick = function() M.OpenGIFSearch(chat) end
    settings.DoClick = function()
        if ZCGoobApps and ZCPhoneSettings then
            ZCGoobApps.State.settings = ZCGoobApps.State.settings or {}
            ZCGoobApps.State.settings.tab="Phone";ZCGoobApps.State.settings.phoneSection="Media";ZCGoobApps.State.settings.query=""
            M.ClosePicker();chat:SetPhonePage("settings")
        else M.OpenPicker(chat,"settings") end
    end
    back.DoClick = shell.Close
    local body = vgui.Create("DPanel", shell)
    body.Paint = function() end
    body.Close = shell.Close
    shell.Think = function(self)
        if not IsValid(chat) or not chat:GetActive() or chat.phonePage ~= "chat" then self:Close(); return end
        local _, inputY = chat.entrySlot:GetPos()
        self:SetPos(6, chat.ZCThreads and 92 or 46)
        self:SetSize(chat:GetWide() - 12, math.max(100, inputY - (chat.ZCThreads and 100 or 54)))
        back:SetPos(self:GetWide() - 60, 8)
        body:SetPos(8, 44); body:SetSize(self:GetWide() - 16, self:GetTall() - 50)
        local t = math.Clamp((RealTime() - self.ZCOpenedAt) / 0.16, 0, 1)
        self:SetAlpha(255 * t * t * (3 - 2 * t))
        self:MoveToFront()
    end
    shell.OnRemove = function() if M.Picker == shell then M.Picker = nil end end
    shell:Think()
    return body, shell
end

function M.OpenPicker(chat, selected)
    if not IsValid(chat) or not chat:GetActive() then return end
    if not selected and IsValid(M.Picker) then M.Picker:Close(); return end
    selected = selected or "emoji"
    local frame = M.CreatePicker(chat, selected)
    if selected == "settings" then
        local options = vgui.Create("DScrollPanel", frame); options:Dock(FILL)
        local function toggle(title, convar)
            local check = options:Add("DCheckBoxLabel")
            check:Dock(TOP); check:DockMargin(8, 8, 8, 4); check:SetTall(24)
            check:SetText(title); check:SetConVar(convar)
        end
        toggle("Show inline media and links", "zc_chat_inline_media")
        toggle("Show images and GIFs", "zc_chat_gifs")
        toggle("Play videos in chat", "zc_chat_videos")
        local volume = options:Add("DNumSlider")
        volume:Dock(TOP); volume:SetTall(36); volume:SetText("Video volume")
        volume:SetMin(0); volume:SetMax(100); volume:SetDecimals(0); volume:SetConVar("zc_chat_video_volume")
        return
    end
    local find = vgui.Create("DTextEntry", frame)
    find:Dock(TOP); find:SetTall(30); find:DockMargin(0, 0, 0, 6)
    find:SetPlaceholderText("Find an emoji...")
    local credit = vgui.Create("DLabel", frame)
    credit:Dock(BOTTOM); credit:SetTall(22); credit:SetText("Twemoji / CC BY 4.0  ·  Choose to add to your draft")
    credit:SetTextColor(Color(170, 167, 167))
    local scroll = vgui.Create("DScrollPanel", frame); scroll:Dock(FILL)
    local grid = scroll:Add("DIconLayout"); grid:Dock(TOP)
    grid:SetSpaceX(6); grid:SetSpaceY(6)
    local lastQuery
    local function fill()
        local query = find:GetValue()
        if query == lastQuery then return end
        lastQuery = query; grid:Clear()
        local names, seen = {}, {}
        if query == "" then for _, name in ipairs(M.Recent) do names[#names+1]=name; seen[name]=true end end
        for _, name in ipairs(M.SearchEmojis(query)) do if not seen[name] then names[#names+1]=name end end
        for _, name in ipairs(names) do
            local emoji = M.Emojis[name]
            if emoji then
                local button = grid:Add("DButton"); button:SetSize(42,42); button:SetText("")
                button:SetTooltip(":" .. name .. ":"); button:SetKeyboardInputEnabled(false)
                button.Paint = function(panel, w, h)
                    draw.RoundedBox(0,0,0,w,h,Color(150,0,0,panel:IsHovered() and 140 or 35))
                    surface.SetDrawColor(255,255,255); surface.SetMaterial(emoji.material)
                    surface.DrawTexturedRect(5,5,w-10,h-10)
                end
                button.DoClick = function()
                    if M.Insert(chat.entry,name) then M.NoteRecent(name); frame:Close()
                    else credit:SetText("Your draft is full. Remove some text first.") end
                end
            end
        end
        if #names == 0 then credit:SetText("No matching emojis. Try another word.")
        else credit:SetText("Twemoji / CC BY 4.0  ·  Choose to add to your draft") end
    end
    find.OnChange=fill; find.OnValueChange=fill; fill(); find:RequestFocus()
end

function M.InstallButton(chat)
    if not IsValid(chat) or not IsValid(chat.entry) then return end
    local button = chat.ZCEmoteButton
    if not IsValid(button) then
        button = vgui.Create("DButton", chat.entry:GetParent())
        chat.ZCEmoteButton = button
        button:Dock(RIGHT)
    end
    button:SetWide(32); button:DockMargin(0, 4, 4, 4); button:SetText("")
    button.Paint = function(panel, w, h)
        local shade = panel:IsHovered() and Color(192, 0, 0, 255) or Color(150, 0, 0, 245)
        draw.RoundedBox(0, 0, 0, w, h, shade)
        draw.SimpleText("+", "DermaLarge", w / 2, h / 2 - 1,
            color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    button:SetTooltip("Emojis and GIF search")
    button.DoClick = function() M.OpenPicker(chat) end
    M.InstallPill(chat)
    M.InstallComplete(chat)
end

-- GIPHY searches execute on the client; no search relay or game-server work.
local giphyMark = {sha="4b9f52d5f524fa22a9666d366bd115e68fd22f2acda9a67c09d96e92d258491a",data="iVBORw0KGgoAAAANSUhEUgAAAMgAAAAaCAYAAADyrhO6AAAACXBIWXMAAAsTAAALEwEAmpwYAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAABXlJREFUeNrsXDGMG0UUnUsCOBHgpUFGSNh029mIApMmi5QiFWe6dGcoclTcUSDR5agpzhESilM5HR2+zl32umsi7XVGOok9UbAFxR5KyEIUzE54Cz+fv95de33nmHnSyN6ZnZ3Zmf/+f3/OydpkMlEGBgYyLpglOC3ccQvdfvTgZfX1Dw9wta36fc+soSHIKuNKobv/fCayW2b5DEFWGp8pdaw/ryoVfhiXzA6PnmhSNHHVVZubTvzpxpHENatpCLJy+EapOj4HE3VjJ7PDt08JcQ9XG6TFEMQQxCAFDUSSsGBO0o1LJy7rQtteXHoC8booFE4Bouooqec4xGfWs7dz3udgvi1WP0S9yvEMD+MZgqwYNlD2mbGmQRvRgEg1Cesod2E04T9knJ435cmp9HNvgoTdjGdbokOQx9Fk2BLmo+t91l+Tpsru7eVd8HPG5lYWLXj5ZgHy9RY0l3UYb1lwQTqOgUCEqhAxc8/FRJDlhfaEX9GKL/bf3/zl98iyXrz09m52/4FgHBonkBgt1n6YV3bMiCuIIoOSntfFGlXZGB0QQJKUJ4LcMgR5LtHv681/Jpn/+a3+1snjoPL4yRuv5jCepmAcHZY7OCRqOCrP6Vo67jLj3xYMtFMiQUK85/dC1PCm5CPhoghyLS41VncQlzHRe/SeMTYjiMt1TGzEJusSzdhC0exvC2MF6C95gGQeNcxBCUlZILT5Kcmm9K4+ntNh/Srk/YaL5MwrL7z+8MK5l6yL56sPM27tCHWOkAS7WHNrTnJIa5nsbT0jz5gHQ0gmSsQ6xq7PI61mIUiNLISGDcO4DSPpwgiHuG6jTrdHuHbx3QahWowgyUbxsRRL8HyUZJwkGavgu8c2PBTaajCahuDVaphLYlDJGAGKA0ImpGvgPReKd1776Cj+eDMuRxm3OoJxeFNOdbJOk+bx8vWc9/YEkjZy9NvG+1YZSeaSVrNKLOoltNf+EsZu4+VuM6+dTP4ABLBRbxOSKWK8bg7vzttCGCklm8fIRRebtrVJtAiEzeVypII6G156RJLhYIkEWlWIoFknQ2V6eStF5k1Dc8axEim6myE5w9MgiLSQEQyMG3OEyVswnpARxMdm2TA8vpEt5kECJtEST98m7VQiReR6lPIOB7jXFgy8hoWt4LtP5jcknjhQ5o93GjdRsiTRItCDw5KIvzfPuEUJQo22ASP0UnR/QhJq/A6eUYHRXicECQqw3GEywofkaZS46BGRcRZIUiH1HsmZlh2NJZjDYYkJelqU+JHVHc8qrWYlSEjkyRhGEsG4W/DIEZFNNkniPWLYIfqMGWG4LEjzzB4hpu77HWsfTZFYFG3yLmqKxPJB5g4ZKxQi17LgkEmWDsnvdtjpmKuK/pBytvlknZJ9ruS/pG8UkFpSXXiaBEnLC0ZEcoxJtFEsVwjgiUfE0NuCvEoM2mEG6zGiamP9VP33fJ3LM19oszEXL8XILZJ3tJaYDBJcRpAq6riRWiWeLB0LRprYS57IITlE56wXsghBpkkgH4tApU9yzBuyjWsTEgUkCkVsrJqQg3CvEGLca+S5vrDxCTlpWwSiHqS8K406geAcwhSvtQzQmnxLSIJ9SMIQ+9QsccwBi0wrgSIEGeWILlmeYizImWHBsQaCMQ+mtKucbUXelcq8ZYQPybIrnG5t5OhrAJjfYq0udBS5VbDPx4YghiD/J+i/Q32g/v717zTs4b6BWbL5knSD5w9Jcm6pf3/OY5FDDy8lt9zJyCnW5phT1rOL3lfGnAxBzhQ/XX76T25VZLXWfp0tmX3vE1W59Js6vvhI/XGjePfk2No1m1GAcea//Tmlhb6vylzo/cm7Z38EanIQAwMTQUwEMTBIw18CDAAYmZzcjwTs3QAAAABJRU5ErkJggg=="}
local markBytes = util.Base64Decode(giphyMark.data)
if markBytes and util.SHA256(markBytes) == giphyMark.sha then
    local path = "zc_chat_media_v1/powered-by-giphy.png"
    local old = file.Read(path, "DATA")
    if not old or util.SHA256(old) ~= giphyMark.sha then file.Write(path, markBytes) end
    local mat = Material("../data/" .. path, "smooth")
    if mat and not mat:IsError() then M.GiphyAttribution = mat end
end

function M.GetGiphyKey()
    local config
    if file.Exists("zc_chat_media/giphy_config.lua", "LUA") then
        config = include("zc_chat_media/giphy_config.lua")
    end
    local key = istable(config) and config.apiKey or ""
    if type(key) ~= "string" or #key < 8 or #key > 128 or key:find("[^A-Za-z0-9_%-]") then return nil end
    return key
end

function M.QueryURL(key, query, offset)
    if type(key) ~= "string" or #key < 8 or #key > 128 or key:find("[^A-Za-z0-9_%-]") then return nil end
    if type(query) ~= "string" or #query > 200 or query:find("[%z\1-\31\127]") then return nil end
    local count = utf8.len(query)
    if not count or count > 50 then return nil end
    offset = tonumber(offset)
    if not offset or offset ~= math.floor(offset) or offset < 0 or offset > 492 then return nil end
    local endpoint = query == "" and "trending" or "search"
    local url = "https://api.giphy.com/v1/gifs/" .. endpoint .. "?api_key=" .. key .. "&limit=12&offset=" .. offset .. "&rating=pg-13&bundle=messaging_non_clips"
    if query ~= "" then
        url = url .. "&q=" .. query:gsub("([^A-Za-z0-9%-._~])", function(c) return string.format("%%%02X", string.byte(c)) end)
    end
    return url
end

function M.SearchRows(result)
    if not istable(result) or not istable(result.data) or not istable(result.pagination) then return nil end
    if not istable(result.meta) or tonumber(result.meta.status) ~= 200 then return nil end
    local rows = {}
    for i = 1, math.min(#result.data, 12) do
        local item = result.data[i]
        local images = istable(item) and istable(item.images) and item.images or {}
        local function rendition(name)
            local value = images[name]
            local url = istable(value) and M.GIFURL(value.url) or nil
            if url and not url:find("https://media.tenor.com/", 1, true) then return url end
        end
        -- Preserve result order; unavailable media keeps its slot.
        rows[i] = {title = istable(item) and tostring(item.title or "GIF") or "GIF",
            preview = rendition("fixed_width_small") or rendition("fixed_height_small"),
            url = rendition("fixed_width") or rendition("fixed_height")}
    end
    local total = math.max(0, math.floor(tonumber(result.pagination.total_count) or 0))
    return rows, total
end

function M.SearchHTML(rows)
    local html = {[[<!doctype html><html><head><meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https://media.giphy.com https://i.giphy.com https://media0.giphy.com https://media1.giphy.com https://media2.giphy.com https://media3.giphy.com https://media4.giphy.com; script-src 'nonce-zc-gif-grid'; style-src 'unsafe-inline'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<style>html,body{margin:0;background:#161e2b;color:#dceafa;font:12px sans-serif}#grid{display:flex;flex-wrap:wrap;gap:6px;padding:6px}button{box-sizing:border-box;width:calc(33.333% - 4px);height:105px;border-radius:10px;border:1px solid #35465e;background:#1e2a3b;color:#eee;padding:3px;cursor:pointer;overflow:hidden}button:hover{border-color:#42baff}button:disabled{cursor:default;opacity:.6}img{width:100%;height:77px;object-fit:contain;pointer-events:none}span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}</style></head><body><div id="grid">]]}
    for i, row in ipairs(rows) do
        local title = M.HTMLText(row.title)
        html[#html + 1] = '<button data-index="' .. i .. '" title="' .. title .. '"' .. (row.url and '' or ' disabled') .. '>'
        if row.preview then html[#html + 1] = '<img referrerpolicy="no-referrer" alt="GIF preview" src="' .. M.HTMLText(row.preview) .. '">' end
        html[#html + 1] = '<span>' .. (row.preview and title or "Preview unavailable") .. '</span></button>'
    end
    html[#html + 1] = [[</div><script nonce="zc-gif-grid">document.getElementById('grid').addEventListener('click',function(e){var b=e.target;while(b&&b.tagName!=='BUTTON'){b=b.parentNode;}if(b&&!b.disabled&&window.zcgif){zcgif.pick(Number(b.getAttribute('data-index')));}});</script></body></html>]]
    return table.concat(html)
end

function M.InsertGIF(entry, url)
    if not M.GIFURL(url) then return false end
    -- Surround the URL so selecting in the middle of a draft stays a distinct link.
    return M.InsertText(entry, " " .. url .. " ")
end

function M.OpenGIFSearch(chat)
    if not IsValid(chat) or not chat:GetActive() then return end
    M.Stop()
    local frame, shell = M.CreatePicker(chat, "gifs")
    local serial, rows, offset, lastQuery, busy, total = 0, {}, 0, "", false, 0
    local browser
    local function active()
        return ZCChatMedia == M and IsValid(frame) and M.Picker == shell and IsValid(chat) and chat:GetActive()
    end
    local function clearBrowser()
        if IsValid(browser) then browser:Remove() end
        browser = nil; rows = {}
    end
    frame.OnRemove = function()
        serial = serial + 1; clearBrowser()
    end
    frame.OnClose = function() if IsValid(chat) and chat:GetActive() then chat.entry:RequestFocus() end end
    local query = vgui.Create("DTextEntry", frame)
    query:SetPos(12, 34); query:SetSize(394, 26); query:SetPlaceholderText("Search for a GIF...")
    local search = M.PickerButton(frame, "Search")
    search:SetPos(412, 34); search:SetSize(62, 26); search:SetText("Search")
    local trending = M.PickerButton(frame, "Trending")
    trending:SetPos(480, 34); trending:SetSize(68, 26); trending:SetText("Trending")
    local status = vgui.Create("DLabel", frame)
    status:SetPos(12, 65); status:SetSize(536, 26); status:SetText("Search or browse trending GIFs. Click a result to add it to your draft.")
    local previous = M.PickerButton(frame, "Previous")
    previous:SetPos(12, 448); previous:SetSize(82, 28); previous:SetText("Previous")
    local nextPage = M.PickerButton(frame, "Next")
    nextPage:SetPos(100, 448); nextPage:SetSize(82, 28); nextPage:SetText("Next")
    local credit = vgui.Create(M.GiphyAttribution and "DImage" or "DLabel", frame)
    credit:SetPos(348, 448); credit:SetSize(200, 26)
    if M.GiphyAttribution then credit:SetMaterial(M.GiphyAttribution) else credit:SetText("Powered By GIPHY") end
    status:SetWrap(true); status:SetTextColor(Color(182, 179, 179))
    frame.PerformLayout = function(_, w, h)
        query:SetPos(0, 0); query:SetSize(math.max(80, w - 146), 28)
        search:SetPos(w - 140, 0); search:SetSize(64, 28)
        trending:SetPos(w - 70, 0); trending:SetSize(70, 28)
        status:SetPos(0, 32); status:SetSize(w, 36)
        previous:SetPos(0, h - 28); previous:SetSize(64, 26)
        nextPage:SetPos(70, h - 28); nextPage:SetSize(48, 26)
        local creditWidth = math.min(160, math.max(80, w - 132))
        credit:SetPos(w - creditWidth, h - 26); credit:SetSize(creditWidth, creditWidth * 26 / 200)
        if IsValid(browser) then browser:SetPos(0, 70); browser:SetSize(w, math.max(24, h - 104)) end
    end
    local function buttons()
        previous:SetEnabled(not busy and offset > 0)
        nextPage:SetEnabled(not busy and offset + 12 < total and offset < 492)
        search:SetEnabled(not busy); trending:SetEnabled(not busy)
    end
    local function request(text, page)
        if not active() or busy then return end
        local key = M.GetGiphyKey()
        if not key then status:SetText("GIF search is not configured on this server yet."); return end
        local url = M.QueryURL(key, text, page)
        if not url then status:SetText("Use a search of up to 50 characters."); return end
        if M.SearchRequest then status:SetText("Waiting for the previous GIF search to finish."); return end
        if RealTime() < (M.NextSearch or 0) then status:SetText("Please wait a moment before searching again."); return end
        M.NextSearch = RealTime() + 2
        serial = serial + 1; local ticket = serial
        local pending = {}; M.SearchRequest = pending
        local function release() if M.SearchRequest == pending then M.SearchRequest = nil end end
        busy = true; clearBrowser(); total = 0; buttons(); status:SetText("Searching GIPHY...")
        local function current() return active() and serial == ticket and busy end
        local function finish(message)
            if not current() then return false end
            busy = false; status:SetText(message); buttons(); return true
        end
        timer.Simple(12, function() release(); finish("Search timed out. Please try again.") end)
        local started = HTTP({url = url, method = "get", timeout = 10,
            failed = function() release(); finish("Could not reach GIPHY. Please try again.") end,
            success = function(code, body)
                release()
                if not current() then return end
                if code == 429 then finish("GIPHY's search allowance is exhausted. Please try later."); return end
                if code == 401 or code == 403 then finish("GIPHY rejected this server's search key."); return end
                if code ~= 200 or type(body) ~= "string" or #body > 1048576 then finish("GIPHY returned an invalid response."); return end
                local parsed = util.JSONToTable(body)
                local found, count = M.SearchRows(parsed)
                if not found then finish("GIPHY returned an invalid response."); return end
                rows = found; total = count; offset = page; lastQuery = text
                finish(#rows == 0 and "No GIFs found. Try a different search." or "Click a GIF to add its link to your draft. Press Enter in chat to send it.")
                if #rows == 0 then return end
                browser = vgui.Create("DHTML", frame)
                if not IsValid(browser) then status:SetText("The GIF preview browser could not open."); return end
                frame:InvalidateLayout(true)
                browser:SetAllowLua(false); browser:SetKeyboardInputEnabled(false)
                local function pick(index)
                    if not active() or serial ~= ticket then return end
                    if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > #rows then return end
                    local row = rows[index]
                    if row and M.InsertGIF(chat.entry, row.url) then frame:Close()
                    else status:SetText("Not enough room in your draft for this GIF link.") end
                end
                browser.OnDocumentReady = function(panel)
                    if active() and serial == ticket and panel == browser then panel:AddFunction("zcgif", "pick", pick) end
                end
                browser:SetHTML(M.SearchHTML(rows))
            end})
        if started == false then release(); finish("Could not start the GIF search.") end
    end
    search.DoClick = function() request(query:GetText(), 0) end
    query.OnEnter = search.DoClick
    trending.DoClick = function() query:SetText(""); request("", 0) end
    previous.DoClick = function() request(lastQuery, math.max(0, offset - 12)) end
    nextPage.DoClick = function() request(lastQuery, offset + 12) end
    buttons()
    if not M.GetGiphyKey() then status:SetText("GIF search is not configured on this server yet.") end
    query:RequestFocus()
end


hook.Add("Think", "ZCChatMedia_Playback", M.UpdatePlayback)

cvars.AddChangeCallback("zc_chat_gifs", function()
    if not gifs:GetBool() then M.Stop() end
    for row in pairs(M.Rows) do if IsValid(row) then M.Layout(row); row:InvalidateParent(true) end end
end, "ZCChatMedia_Preferences")

cvars.AddChangeCallback("zc_chat_videos", function()
    if not videos:GetBool() then M.StopVideo() end
    for row in pairs(M.Rows) do if IsValid(row) then M.Layout(row); row:InvalidateParent(true) end end
end, "ZCChatMedia_Videos")

cvars.AddChangeCallback("zc_chat_video_volume", function() M.ApplyVideoAudio() end, "ZCChatMedia_Videos")
cvars.AddChangeCallback("zc_chat_inline_media", function() M.RefreshInlineMedia() end, "ZCChatMedia_InlinePreference")

-- The chat panel survives a module re-include, so rebind its Media button.
if hg and IsValid(hg.chat) then M.InstallButton(hg.chat) end

-- Conversation state stays in the chat owner; no persistence of private text to disk.
function M.ChainKey(speaker)
    if not IsValid(speaker) then return nil end
    local identity = speaker:IsBot() and ("bot:" .. speaker:UserID()) or speaker:SteamID64()
    return tostring(identity)
end
function M.ChainPosition(entries, key, now)
    local count = #entries
    if not key or not Grouping:GetBool() then return count + 1, false end
    local last = entries[count]
    if IsValid(last) and last.ZCChainKey == key then
        return count + 1, true
    end
    -- Only cross one briefly intervening chain; anchor its FIRST arrival so
    -- repeated A/B replies cannot keep postponing the same person indefinitely.
    local interruption = last and last.ZCChainKey
    local first = count
    while first > 1 and entries[first - 1].ZCChainKey == interruption do first = first - 1 end
    local prior = entries[first - 1]
    if IsValid(prior) and prior.ZCChainKey == key and now - (entries[first].ZCArrived or 0) <= 4 then return first, true end
    return count + 1, false
end
function M.ReflowChains(chat)
    local previousRow
    for i, row in ipairs(chat.entries) do
        if IsValid(row) then
            local grouped = previousRow and previousRow.ZCChainKey == row.ZCChainKey and row.ZCChainKey ~= nil
                and Grouping:GetBool()
            if row.ZCGrouped ~= (grouped == true) then
                row.text = grouped and (row.ZCGroupedText or row.text) or (row.ZCFullText or row.text)
            end
            row.ZCGrouped = grouped == true
            row.ZCLeftInset = grouped and 8 or (IsValid(row.ZCAvatar) and ((ZCPhoneSettings and ZCPhoneSettings.AvatarSize() or 40)+8) or 8)
            if IsValid(row.ZCAvatar) then row.ZCAvatar:SetVisible(not grouped) end
            row.ZCTopGap = previousRow and (grouped and 2 or (ZCPhoneSettings and ZCPhoneSettings.Get("gap") or 12)) or 0
            row:DockMargin(0, row.ZCTopGap, 0, 0)
            row:SetZPos(i + 1)
            row:InvalidateLayout(true)
            previousRow = row
        end
    end
    chat.history:InvalidateLayout(true)
end
function M.FindMessage(id)
    local chat = hg and hg.chat
    for _, row in ipairs(IsValid(chat) and chat.entries or {}) do
        if IsValid(row) and row.ZCMessageID == id then return row end
    end
end
function M.ReplyLabel(id)
    if M.DeletedIDs[id] then return "Original message removed" end
    local row = M.FindMessage(id)
    if not IsValid(row) then return "Earlier message" end
    -- Local rendered text only. Spoilers stay masked; hidden links stay hidden.
    local text = M.FilterRowText(row, row.ZCGroupedText or row.text or ""):gsub("<[^>]*>", ""):gsub("[\r\n]", " ")
    text = string.utf8sub(text, 1, 90)
    return (row.ZCSenderName or "Player") .. " · " .. text
end
function M.BeginReply(row)
    if not IsValid(row) or not row.ZCMessageID or M.DeletedIDs[row.ZCMessageID] then return end
    local chat = hg and hg.chat
    if not IsValid(chat) then return end
    chat.ZCReplyID = row.ZCMessageID
    chat:SetActive(true)
    chat.entry:RequestFocus()
end
function M.MentionSender(row)
    local chat = hg and hg.chat
    if not IsValid(row) or not IsValid(chat) or not IsValid(row.ZCSpeaker) then return end
    chat:SetActive(true)
    local text = chat.entry:GetText()
    text = text .. (text ~= "" and " " or "") .. "@" .. row.ZCSpeaker:Nick() .. " "
    chat.entry:SetText(text); chat.entry:SetCaretPos(#text); chat.entry:RequestFocus()
end
function M.UpdateReplyComposer(chat)
    local show = chat:GetActive() and chat.phonePage == "chat" and chat.ZCReplyID ~= nil
    if chat.ZCReplyID and M.DeletedIDs[chat.ZCReplyID] then chat.ZCReplyID = nil; show = false end
    if not IsValid(chat.ZCReplyBar) then
        local panel = vgui.Create("DButton", chat)
        chat.ZCReplyBar = panel
        panel:SetText(""); panel:SetKeyboardInputEnabled(false)
        panel:SetTooltip("Cancel reply")
        panel.DoClick = function() chat.ZCReplyID = nil; chat.entry:RequestFocus() end
        panel.Paint = function(_, w, h)
            draw.RoundedBox(0, 0, 0, w, h, Color(60, 57, 57, 230))
            draw.SimpleText("↩ " .. M.ReplyLabel(chat.ZCReplyID) .. "    ×", "DermaDefault", 8, 7, Color(216, 213, 213))
        end
    end
    chat.ZCReplyBar:SetVisible(show)
    if chat.ZCReplyComposerShown ~= show then
        chat.ZCReplyComposerShown = show
        chat.history:DockMargin(4, 2, 4, show and 44 or 12)
        chat:InvalidateLayout(true)
    end
    if show then
        local x, y = chat.entrySlot:GetPos()
        chat.ZCReplyBar:SetPos(x + 4, y - 32)
        chat.ZCReplyBar:SetSize(chat.entrySlot:GetWide() - 8, 26)
        chat.ZCReplyBar:MoveToFront()
    end
end
function M.AttachReply(row)
    if not row.ZCReplyID or row.ZCReplyID == 0 then return end
    local quote = vgui.Create("DButton", row)
    row.ZCQuote = quote; quote:SetText(""); quote:SetKeyboardInputEnabled(false)
    quote:SetTooltip("Jump to original message")
    quote.Paint = function(_, w, h)
        local alpha = M.Alpha(row)
        draw.RoundedBox(0, 0, 0, w, h, Color(192, 0, 0, alpha * .16))
        draw.SimpleText("↩ " .. M.ReplyLabel(row.ZCReplyID), "DermaDefault", 6, 7, Color(223, 220, 220, alpha))
    end
    quote.DoClick = function()
        local original = M.FindMessage(row.ZCReplyID)
        if IsValid(original) then
            hg.chat.history:ScrollToChild(original)
            original.ZCHighlightUntil = CurTime() + 1
        end
    end
end
function M.CaptureHistory(chat)
    if not IsValid(chat) then return end
    local saved = {rows = {}, recall = chat.messageHistory, draft = chat.entry:GetText(), reply = chat.ZCReplyID,
        active = chat:GetActive(), page = chat.phonePage}
    for _, row in ipairs(chat.entries or {}) do
        if IsValid(row) then
            local source = row.ZCSourceElements
            if not source then
                -- One-time migration from social6. Preserve exact visible markup.
                source = {IsValid(row.ZCSpeaker) and row.ZCSpeaker or "", ": ", row.ZCReport and row.ZCReport.text or ""}
                if row.ZCGifURL then source[#source + 1] = row.ZCGifURL end
                if row.ZCVideoID then source[#source + 1] = "https://youtu.be/" .. row.ZCVideoID end
            end
            saved.rows[#saved.rows + 1] = {elements = source, speaker = row.ZCSpeaker, name = row.ZCSenderName,
                id = row.ZCMessageID, reply = row.ZCReplyID, bot = row.ZCBot, text = row.text,
                bubble = row.ZCBubble, own = row.ZCOwn, steam = row.ZCSenderSteam or (row.ZCReport and row.ZCReport.steam),
                full = row.ZCFullText, grouped = row.ZCGroupedText, original = row.ZCGifOriginalText,
                fullOriginal = row.ZCFullOriginal, groupedOriginal = row.ZCGroupedOriginal, revealed = row.ZCRevealed,
                arrived = row.ZCArrived, key = row.ZCChainKey, counts = row.ZCReactionCounts, spectator=row.ZCSpectator, censored=row.ZCCensored,
                selected = row.ZCReactionSelected, alpha = row.alpha, report = row.ZCReport,
                mediaAllowed = row.ZCGifURL ~= nil or row.ZCVideoID ~= nil,
                verdict = row.ZCSourceElements and M.Verdicts[row.ZCSourceElements]}
        end
    end
    return saved
end
function M.RestoreHistory(chat, saved)
    if not IsValid(chat) or not saved then return end
    local oldSpeaker, oldID, oldReply, oldBot = CHAT_SPEAKER, CHAT_MESSAGE_ID, CHAT_REPLY_ID, CHAT_IS_BOT
    M.Restoring = true
    local ok, err = pcall(function()
        for _, item in ipairs(saved.rows or {}) do
          if not (item.spectator and ZCChatGroupUI and not ZCChatGroupUI.Spectator() and CHAT_CONVERSATION and CHAT_CONVERSATION~="main") then
            CHAT_SPEAKER, CHAT_MESSAGE_ID, CHAT_REPLY_ID, CHAT_IS_BOT = item.speaker, item.id, item.reply, item.bot
            local row = chat:AddLine(item.elements, item)
            if IsValid(row) then
                row.ZCSpectator=item.spectator;row.ZCCensored=item.censored
                row.ZCReactionCounts = item.counts or row.ZCReactionCounts
                row.ZCReactionSelected = item.selected
                row.ZCRevealed = item.revealed
                if row.ZCRevealed and IsValid(row.ZCReveal) then row.ZCReveal:Remove(); row.ZCReveal = nil end
                row.ZCReport = item.report or row.ZCReport
                row.ZCTypewriterStart = CurTime() - 100
                row.alpha = item.alpha or 0
                M.LayoutReaction(row)
            end
          end
        end
    end)
    M.Restoring = false
    CHAT_SPEAKER, CHAT_MESSAGE_ID, CHAT_REPLY_ID, CHAT_IS_BOT = oldSpeaker, oldID, oldReply, oldBot
    if not ok then ErrorNoHalt("Chat history restore: " .. tostring(err) .. "\n") end
    chat.messageHistory = saved.recall or {}
    chat.entry.History = chat.messageHistory
    chat.entry:SetText(saved.draft or ""); chat.entry.prevText = saved.draft or ""
    chat.ZCReplyID = saved.reply
    M.ReflowChains(chat)
    if saved.active then chat:SetActive(true); chat:SetPhonePage(saved.page or "chat", true) end
end

local captureConversation = M.CaptureHistory
local restoreConversation = M.RestoreHistory
function M.CaptureHistory(chat) return ZCChatThreads.Export(chat,captureConversation) end
function M.RestoreHistory(chat,saved) return ZCChatThreads.Import(chat,saved,restoreConversation) end
