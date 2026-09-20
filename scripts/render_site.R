source(file.path("R", "load_all.R"))
source_project_modules(".")
output <- render_student_site(".")
cat(paste(output, collapse = "\n"), "\n")

