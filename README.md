# pratt-parser-tutorial

A zig implementation of [matklad's][matklad-github] minimal pratt parser. The video shows how each
section of the code maps to a specific part of the original academic paper. 

- Matklad's blog tutorial- [Simple but Powerful Pratt Parsing][matklad-blog] 
- Blog repository - [matklad/minipratt][matklad-blog-repository]
- Original academic paper - [Top Down Operator Precedence][pratt-parser-academic-paper]

The second part of the video follows data-oriented design, reducing the memory usage of the parser
as much as possible. To understand this section, these discussions are a prerequisite:

- Andrew Kelley's (Creator of Zig) Talk - 
[Andrew Kelley Practical Data Oriented Design (DoD)][dod-talk]
- How the Zig parser works - [Mitchell Hashimoto's blog post][zig-parser]

[matklad-github]: https://github.com/matklad
[matklad-blog]: https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
[matklad-blog-repository]: https://github.com/matklad/minipratt
[pratt-parser-academic-paper]: https://dl.acm.org/doi/pdf/10.1145/512927.512931
[dod-talk]: https://www.youtube.com/watch?v=IroPQ150F6c
[zig-parser]: https://mitchellh.com/zig/parser#how-parsing-works
