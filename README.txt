AutoSite (c) Copyright wlindley.com, l.l.c.

This documentation may be distributed under the terms of the GNU
Free Documentation License available at

  http://www.gnu.org/copyleft/fdl.html

-----------------------------------------------------------------

Document Version 0.2, 2005-02-28

AutoSite is a Perl script, a Content Management System that spiders a
local website and performs a variety of functions that simplify
managing nontrivial sites, large or small.

Usage:

  autosite.pl [-c config_file.htm] mainfile.htm

Can specify full pathnames to either config file or main HTML file.
AutoSite handles relative or absolute pathnames and changes them all
to paths relative to the document root (Table of Contents) which in
this case is mainfile.htm.

Options:

  -c template     Use specified sitewide template
  -w              Display warnings
  -n              Force navigational <link> elements into all files

Definitions:

Local file: A file whose URL does not start with a protocol ("http:")
  is assumed to be local, i.e., within the current project's directory
  tree.


Features:

AUTOMATIC 'ALT' TEXT

The ALT attribute of an IMG within an <A> anchor will be set to the
title of the linked page, if the page is local.

PICTURE SIZES

<img> tags calling for jpeg (*.jpe?g) and gif images (*.gif) will have
their width and height attributes set.  This currently conflicts with
using styles: <img style="width: 320px; height: 240px">

WEBSITE HIERARCHICAL STRUCTURE

The document root, or Table of Contents (TOC) node, (usually
index.html, but whatever is passed as the command-line argument to
AutoSite) or any other page may declare children by using <a
href="..." rel="child">.  Child relations are:

	   chapter   (should only be declared from the TOC)
	   child
	   section
	   subsection  (see below)
	   glossary
	   appendix

When a page is declared as a child, it automatically gets 'first'
'last' 'next' and 'prev' hierarchical links as appropriate.

Subsections are considered children of the current page but are not
included in the next/previous navigation.  A subsection will have a
parent but no "next" or "previous" page.

Also, the relation 'extra' can be used for pages which need to be
processed as part of the site but not included in the hierarchy
at all.

CHAPTER GROUPS

Adding a division like <div class="chapter_group" title="MyHeading">
around one or more <a href...> links will insert a horizontal rule
above the first link when it is displayed in the navigation bar.  If
the optional title is included, it will be inserted as a paragraph of
class 'chapter_group'

AUTOMATIC TITLING

The text of the first <h1> (or <h2> through <h4>, whichever occurs
first in the flie) will become the <title> of the page.  Line breaks
<br> within that text will become spaces in tht title.  Non-literal
elements like <img> inside the first <h1>-<h4> are ignored for this
purpose.

NAVIGATION BUTTONS

Anchors which declare navigational relations either explicitly (<a
href="..." rel="next">) or implicitly by having containing images
defined as navigational buttons. see %image_relations, currently:

	up, down, left, right, first, last

and these may be followed optionally by 'no' and either '.jpg' '.jpeg'
or '.gif'; and will automatically have their hypertext reference
replaced with the appropriate file from the site's hierarchical
structure.  Specifically,

        ---IMAGE---   --<LINK> USED--
	up.gif	      parent
	down.jpg      head             (this page's first child)
	left.jpeg     prev
	right.gif     next
	first.jpg     first
	last.jpeg     last

This processing also includes the <img alt="..."> tag being replaced
with the title of the linked file.

In the case of a navigational direction which does not point to a
file, <a href="#"> will be set (this just links back to the start of
the current file) and 'no' will be placed in the image filename (e.g.,
'up.gif' will become 'upno.gif') for a visual indicator.

OTHER NAVIGATION

These are the relations that may be declared or used.

      REL=        MAPS TO
      ---------   ------------
      start       Root node / Main page
      contents    Root node / Main page
      parent      Node's parent
      up          Node's parent
      first       First document in current level (oldest sibling)
      prev        Previous document (older sibling)
      next        Next document (younger sibling)
      last        Last document (youngest sibling)
      chapter     Declares child as a chapter  (*)
      section     Declares child as a section (*)
      appendix    An appendix (**)
      glossary    Sitewide Glossary (**)
      index       Sitewide Index (**)
      help        Sitewide Help page (**)
      search      Sitewide Search page (**)

  (*) May only occur in Root node.
  (**) Declares a child as the sitewide page given page (in root node)
     or references that page elsewhere.

NAVIGATIONAL LINKS (HTML 4.0)

The document header <head> may contain <link> tags which define the site
structure.  These are handled by Mozilla 1.0 and other HTML 4.0 browsers
by displaying links in a toolbar.

If a page contains one or more <link rel="..."> tags defined by the
%link_relations array (currently: start, parent, up, first, prev,
next, last, contents, chapter, section, appendix, glossary, index,
help, search), then that page will have all those links automatically
generated according to the website structure.

If the -n command-line switch is used, these navigational <link> tags
will be inserted into all HTML files that AutoSite spiders.  This
generally needs to be done only once on an existing site to "prime the
pump."

TEXT GENERATION.

Use SPAN, DIV, or INS to generate AutoSite text.  Note: INS tags are
underlined in Internet Explorer 5.  The AutoSite script automatically
removes any existing contents inside the span, div, or ins tag and
replaces it with generated text.

  <SPAN class="autosite" ID="method"></SPAN>

See below for full examples.

Example methods

	full_contents|b,ul
	  Insert a full table of contents, with Unordered list tyle.
	  Current node will be bold.
	full_contents|ol=1Aia
	  Insert a full table of contents, with Ordered list style.
	  First item will have TYPE='1' then A, i, a, and repeat.
	  Current node will not be bold.
	sidenav|b,child
	  Insert a Side Navigation bar.
	  Current node will be bold.
	  The current node's children, if any, will be listed.

DECLARING SITEWIDE MACROS

In the site template:

    <DIV ID="macro_name" CLASS="macro">
    Text Here
    </DIV>
    <span id="logos" class="macro">
    <a href="#" rel="toc"><img src="images/home.gif"></a>
    </span>

declares a macro.  <span> is equivalent to <div> here.  The macro can
have any literal text or HTML tags.  The above example takes advantage
of the automatic hierarchical navigation function, by using the <a
rel="toc"> which will replace the href="#" with the correct relative
link to the Table of Contents when used as show below.

USING SITEWIDE MACROS

<div class="autosite" id="makerelative.logos">

where 'logos' is a macro defined in the site template, and
'makerelative' is a function called to turn the value of <a
href="..."> and <img src="..."> tags into the correct relative
locations for the calling file.

<span> works the same as <div> for the AutoSite functionality.  In
most browsers, <div> forces a line break like <p> whereas <span> does
not.

AUTOMATIC SIDEBAR NAVIGATION

<span class="autosite" id="sidenav.nbsp">

where argument can be:

  nbsp    Change spaces in title to nonbreaking spaces
  child   Show the children of the current node (default: do not show)

  indent  Use text-indent property for indenting (default: use nonbreak spaces)
  ol	  Use ordered lists
  ul	  Use unordered lists

These can be combined with dashes:   id="sidenav.nbsp-child-ol-1a"

The 'indent' property can also be, for example, 'indent5' which will
indent each level by 0.5 em.

'ol' when given last in the argument list can optionally have modifier
like '1aI' which would give lists with three levels of identation
type "1", "a", and "i".  However, the use of stylesheets is preferred;
the lists will all have class 'sidenavlist'.

For example, this in the stylesheet will produce indented lists, with
any wrapped text in the entries being *indented*...

    ol.sidenavlist {
      margin-left: 0;
      padding-left: 1em;
    }

    ol.sidenavlist li {
      font-style: italic;
      list-style-type: none;
      padding-left: 1em;
      text-indent: -1em;
    }


The Side Navigation bar uses the Terse Navigation Titles if availble.
These are defined in a file's header with:

   <META CONTENT="short title" NAME="nav_title">

Text emitted in the sidebar will have class="sidenav" and the current
document will have id="current-nav"; these may be declared in your
stylesheet so the text appears bold or however you wish to highlight
it.

AUTOMATIC SITEMAPS

<div class="autosite" id="full_contents.ul">

default is to create a list indented with nonbreak spaces; or use:

  ul      Create nested unordered lists
  ol      Create nested ordered lists

'ol' can be followed by a modifier:

  ol-1Aia   First level is 1,2,3; second is A,B,C; etc.
  
Other modifiers:

  full    List full page titles (default: List Terse Navigation [navtitle] titles)

INHERITING FROM DOCUMENT ROOT.

In META tags, you may use content="*" to inherit that content item from the TOC node; this gets
replace with:  content="*Content from TOC" which will be reprocessed each time.

See also "Inheriting from Template" below.

TEMPLATING.

<link rel="template" href="../template.html>

   will cause the current file's <body> to be replaced with the body
   from the template.  The <div id="content"> from the existing
   current file will be maintained, and placed wherever the template
   has <div id="content">

INHERITING FROM TEMPLATE.

<meta name="inherit" content="stylesheet, copyright">

   when used *after* <link rel="template"> will replace the current
   file's <meta name="copyright"> and <link rel="stylesheet"> with
   those from the template.  NOTE: Most of the <link> relations
   (start, contents, search, etc.)  are handled through the <link>
   logic, and should not be 'inherited.'

   This may also be used in documents without templates, with the
   values coming from the document root.

AUTOMATIC THUMBNAILS.

This is still being added from my AutoThumb script and is, as yet,
incomplete.

Here is how AutoThumb currently works:

# Within the current directory, parameters are read from index.txt:
#
#  THUMB:       0 or 1         # whether to produce thumbnails  
#  THUMB.SIZE:  n or  100x100  # sets maximum pixel count, or maximum x,y size 
#  THUMB.DIR:   thumbdir/      # thumbnail directory
#  MEDIUM:      0 or 1         # whether to produce medium size pictures
#  MEDIUM.SIZE: n or  100x100  # sets maximum pixel count, or maximum x,y size
#  MEDIUM.DIR:  meddir/        # medium picture directory
#  LIST.TYPE:                  # 'p' for each image in its own paragraph
#                              # 'table' for multicolumn table
#                              # 'ul' for bulleted text list
#  LIST.COLUMNS: n             # number of columns
#  LIST.IMAGE:                 # 'thumb' for thumbnails
#                              # 'medium' for medium pictures
#  LIST.BORDER:  n             # border size for image list
#  LINKSTYLE:                  # 'medium' for links to medium sized pics
#                              # 'full' for links to full (original) sized pictures
#                              # 'none' for no links at all
#                              # NOTE: if a .txt file exists for an image, that
#                              # overrides 'linkstyle' and a link will be made to
#                              # the page generated by that file and the template.
#  LINK.TARGET  _blank         # to display linked images in a new frame
#  SHOWSIZE:    0 or 1         # enable for "nnn files, totalling nnn bytes" message
#  SHOWNAME:    0 or 1         # enable to display link name in list
#  TEMPLATE:    filename       # path and filename to template file
#  IMAGES:      file,file,...  # list of filenames, or wildcards --   IMAGES: *.jpg

Additional parameters of any name may be used, and will be available
as a Substitution in the template file.  The template file may contain
substitutions in the form:

    [:varname:]

which will substitute the contents of the named variable.  This is
especially useful when combined with the fact that AutoThumb reads a
text file for each image file which can contain one or more variables.
For an image brogmoid1.jpeg, the text file would be brogmoid1.txt and
it would be formatted like this:

     H1: Brogmoid Earwax
     location: La Brea Tar Pits, CA
     date: Early Spring 2003

The template then would have something like:

    ...
    <body>
    <h1>[:h1:]</h1>
    <h2>[:location:]</h2>
    <em>[:date:]</em>
    ...

Note that the parameter names are all converted, when read, to
lowercase.  Longer passages of text in the image text file may use
"here documents" like this:

    DESCRIPTION:  <<ENDTEXT
    The Brogmoids were famous for the prodigious amount
    of earwax they produced.
    ENDTEXT

Presumably, in AutoSite, we will use a filename like thumbnail.conf
(instead of index.txt) in the directory of the Document Root to set
global defaults; each subdirectory may contain a thumbnail.conf which
overrides one or more parameters.
